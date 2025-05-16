#!/usr/bin/perl

use strict;
use warnings;
use File::Find;
use Cwd;
use File::Basename;
use POSIX qw(strftime);
use Sys::Hostname;
use Getopt::Long;
use File::Path qw(make_path);
use Excel::Writer::XLSX;
use File::Glob qw(glob);
use Spreadsheet::XLSX;
use Spreadsheet::ParseExcel;

my ($netlist_ver, $corner, $list, $help);
my $output_file = "timing_violations.xlsx";
my $detailed_text_file_path = "timing_violations_detail.txt";

GetOptions(
    "netlist_ver=s" => \$netlist_ver,
    "corner=s" => \$corner,
    "list=s" => \$list,
    "help|h" => \$help,
) or die print_help();

# Display help if requested
if ($help) {
    print print_help();
    exit;
}

# Validate required arguments
die print_help() unless defined $netlist_ver && defined $corner && defined $list;

# Validate corner values
my @valid_corners = qw(TYP_MAX TYP_MIN MAXMAX MINMIN);
if (defined $corner && !grep { $_ eq $corner } @valid_corners) {
    print "ERROR: Invalid corner '$corner'. Valid values are: " . join(", ", @valid_corners) . "\n\n";
    die print_help();
}

# Validate list values
my @valid_lists = qw(hp sanity hpio);
if (defined $list && !grep { $_ eq $list } @valid_lists) {
    print "ERROR: Invalid list type '$list'. Valid values are: " . join(", ", @valid_lists) . "\n\n";
    die print_help();
}

# Create the base directory structure
my $base_dir = "/scratchV/eagle_sdf_timing_violations_check/eagle_chiptop";
my $target_dir = "${base_dir}/${netlist_ver}_${corner}";
my $result_dir = "${target_dir}/${list}";

make_path($result_dir) or die "Failed to create directory: $result_dir\n";

# Store the regression directories
my @directories = @ARGV;
my @regression_directories = ();
foreach my $arg (@ARGV) {
    if (-d $arg) {
        my $parent_dir = $arg;
        $parent_dir =~ s/\/[^\/]+$//;
        unless (grep { $_ eq "$parent_dir/*" } @regression_directories) {
            push @regression_directories, "$parent_dir/*";
        }
    }
    elsif ($arg =~ /^\//) {
        push @regression_directories, $arg;
    }
}

# Format timestamp for file names
my $timestamp = strftime("%d-%m-%Y %H:%M:%S", localtime);
$timestamp =~ s/[- :]//g;

# Create file names with timestamp
my $excel_file = "$result_dir/timing_violations_${timestamp}.xlsx";
$detailed_text_file_path = "$result_dir/timing_violations_detail_${timestamp}.txt";

# Find most recent previous Excel file for comparison
my $previous_file = find_previous_excel_file($result_dir, $timestamp);

my $server_name = hostname();
my $region = ($server_name =~ /vncsrv/i) ? "US" : $server_name;
my $report_date = strftime("%d-%m-%Y %H:%M:%S", localtime);

my $specific_file_pattern = 'local_log.log';
my @keywords = (
    'UVM_WARNING : 0',
    'UVM_ERROR : 0',
    'UVM_FATAL : 0'
);

# Patterns to exclude: Test IDs with these patterns are excluded from processing.
my @exclude_patterns = (qr/^soc_lp_upf/, qr/^stby_stop/, qr/^fast_gpio/, qr/^wounding_lp/, qr/^reset_upf/, 
                        qr/on_the_fly_porstn/, qr/porstn_es0_es1_regs_chk$/, qr/warm_rst/,
                        qr/on_the_fly_sw_rst/, qr/exptmst0_onff/, qr/onoff/, qr/^efuse_stop/, qr/^efuse_stby/);

# Exact Tests to exclude: These are specific test IDs that need to be excluded.
my @excluded_Test_IDs = qw(mhu27 ewic1 firewall17 design_sanity15 design_sanity17 camera71 mipidsi6 cdc23 
                           lp_ymn_hscmp efuse_itcm efuse_hp_boot efuse_lp_boot efuse_rd_ocvm efuse_rd_cvm 
                           efuse_v18encheck design_sanity2 design_sanity3 design_sanity5 design_sanity6 
                           design_sanity8 design_sanity9 fullchip_on_the_fly_epor_poresetn_pin 
                           host_sys_sw_rst_regs_chk zaphod_hard_reset design_sanity0 i3c_on_off 
                           chip_debug6 chip_debug15 wounding_11 design_sanity1 design_sanity4 
                           eth_rmii_rx_systop_pwr_on_off 
                           LPUART_32Byt_TxRx_921600Kbps_PowOnOff_LPYAMIN_LPDTCM_GPIOA 
                           es0_es1_porstn_regs_chk es0_es1_porstn_btwn_local_cpu_internal_tcm_xfers 
                           wounding_16 expmst0_gpiox_pwr_on_off wounding_18 jpeg01 dave14 
                           LPI2C_Pow_On_Off_LPYmn_GPIOA lpcmp_upf_irq_test1 usb21 sdc_pwr_on_off);

# Check if a test ID matches any exclude pattern or exact word
sub is_excluded {
    my ($test_id) = @_;
    
    # Check if the test ID matches any pattern
    foreach my $pattern (@exclude_patterns) {
        return 1 if $test_id =~ /$pattern/;
    }
    
    # Check if the test ID matches any exact word
    foreach my $word (@excluded_Test_IDs) {
        return 1 if $test_id eq $word;
    }
    
    return 0;
}

my @all_results;
my %unique_flops;
my $count = 1;
my @files_without_reset;
my $total_tests = 0;
my $total_files_analyzed = 0;
my $total_passed_logs = 0;
my $total_skipped_logs = 0;
my @excluded_test_ids;

sub escape_csv {
    my $field = shift;
    return '' unless defined $field;
    if ($field =~ /[,"\\r\\n]/) {
        $field =~ s/"/"/g;
        $field = qq{"$field"};
    }
    return $field;
}

sub process_log_file {
    my $file_path = shift;
    
    my %results = (
        'test_id' => '',
        'uvm_testname' => '',
        'timing_violations' => 0,
        'test_path' => $file_path,
        'test_name' => basename(dirname($file_path)),
        'unique_violations' => [],
    );
    
    open(my $fh, '<', $file_path) or die "Can't open file $file_path: $!\n";
    my $file_content = do { local $/; <$fh> };
    close($fh);
    
    if ($file_content =~ /-test_id\s+(\S+)/) {
        $results{'test_id'} = $1;
    }
    
    if ($file_content =~ /\+UVM_TESTNAME\s*=\s*(\S+)/) {
        $results{'uvm_testname'} = $1;
    }
    
    my $tb_reset_released = ($file_content =~ /CHIP POR RESET IS RELEASED/);
    if ($tb_reset_released) {
        print "Found CHIP POR RESET IS RELEASE in $results{test_name}\n";
    } else {
        print "NOT Found CHIP POR RESET IS RELEASE in $results{test_name}\n";
        push @files_without_reset, $file_path;
    }
    
    my $after_tb_reset = 0;
    open(my $line_fh, '<', $file_path) or die "Can't open file $file_path: $!\n";
    my $line_num = 0;
    
    while (my $line = <$line_fh>) {
        $line_num++;
        chomp $line;
        
        if ($line =~ /CHIP POR RESET IS RELEASED/) {
            $after_tb_reset = 1;
        }
        
        if ($after_tb_reset && $line =~ /Warning! Timing violation/) {
            $results{'timing_violations'}++;
            
            <$line_fh>; <$line_fh>; # Skip next two lines
            
            my $scope_line = <$line_fh>;
            if (defined $scope_line) {
                my $time_line = <$line_fh>;
                my $viol_time = "";
                
                if ($time_line && $time_line =~ /Time:\s+(\d+\s+\w+)/) {
                    $viol_time = $1;
                }
                
                if ($scope_line =~ /Scope:(.*)/) {
                    my $scope = $1;
                    $scope =~ s/^\s+|\s+$//g;
                    
                    unless (exists $unique_flops{$scope}) {
                        push @{$results{'unique_violations'}}, {
                            line_num => $line_num,
                            count => $count,
                            scope => $scope,
                            viol_time => $viol_time,
                        };
                        $unique_flops{$scope} = 1;
                        $count++;
                    }
                }
            }
        }
    }
    
    close($line_fh);
    
    if (@{$results{'unique_violations'}}) {
        push @all_results, \%results;
    }
}

# Create Excel workbook
my $workbook = Excel::Writer::XLSX->new($excel_file);
die "Failed to create Excel file: $!" unless $workbook;

# Get month abbreviation and date for sheet names
my ($year, $month, $day) = (localtime)[5, 4, 3]; # Automatic current date
$year += 1900; # Adjust year
$month += 1; # Adjust month
my $month_abbr = qw(J F M A M J J A S O N D)[$month - 1];

my $list_display = $list;
if ($list eq "sanity") {
    $list_display = "SAN";
}

# Create sheet names (convert everything to uppercase)
my $sheet1_name = uc("${list_display}_${netlist_ver}_${corner}_${day}${month_abbr}");
my $sheet2_name = uc("${list_display}_${netlist_ver}_${corner}_${day}${month_abbr}_D");

my $worksheet1 = $workbook->add_worksheet($sheet1_name);
my $worksheet2 = $workbook->add_worksheet($sheet2_name);

# Create a comparison worksheet if previous file exists
my $comparison_sheet = undef;
my %previous_data = ();
my %previous_flops = ();

if ($previous_file) {
    print "Found previous Excel file for comparison: $previous_file\n";
    $comparison_sheet = $workbook->add_worksheet("COMPARISON");
    %previous_data = load_previous_excel_data($previous_file);
}

DIRECTORY:
for my $directory (@directories) {
    unless (-d $directory) {
        warn "Directory '$directory' does not exist -- skipping.\n";
        next DIRECTORY;
    }
    
    print "\n--- Now processing directory: $directory ---\n";
    
    find(
        sub {
            return unless -f $_ && /$specific_file_pattern$/;
            $total_tests++;
            
            open(my $fh, '<', $_) or die "Can't open file $_: $!\n";
            my $content = do { local $/; <$fh> };
            close($fh);
            
            my $matches_all = 1;
            foreach my $keyword (@keywords) {
                unless ($content =~ /\Q$keyword\E/) {
                    $matches_all = 0;
                    last;
                }
            }
            
            if ($matches_all) {
                $total_passed_logs++;
                
                if ($content =~ /-test_id\s+(\S+)/) {
                    my $test_id = $1;
                    
                    if (is_excluded($test_id)) {
                        print "Excluding $_ because test_id '$test_id' matches exclude criteria.\n";
                        push @excluded_test_ids, $test_id;
                        $total_skipped_logs++;
                        return;
                    }
                }
                
                process_log_file($File::Find::name);
                $total_files_analyzed++;
            }
        },
        $directory
    );
}

# Create format objects
my $header_format = $workbook->add_format();
$header_format->set_bold();
$header_format->set_border();
$header_format->set_border_color('black');
$header_format->set_align('center');
$header_format->set_text_wrap();
$header_format->set_align('vcenter');

my $data_format = $workbook->add_format();
$data_format->set_border();
$data_format->set_border_color('black');

my $bold_format = $workbook->add_format();
$bold_format->set_bold();
$bold_format->set_border();
$bold_format->set_border_color('black');

my $highlight_format = $workbook->add_format();
$highlight_format->set_border();
$highlight_format->set_border_color('black');
$highlight_format->set_bg_color('yellow');

$worksheet1->set_column('A:A', 30);

# Write first worksheet
my $row = 0;

# Write report information with formatting
$worksheet1->write($row, 0, "Report Generation timestamp");
$worksheet1->write($row, 1, $report_date);
$row++;

$worksheet1->write($row, 0, "Server");
$worksheet1->write($row, 1, $region);
$row++;

$worksheet1->write($row, 0, "Regression Directory:");
$worksheet1->write($row, 1, join(" ", @regression_directories));
$row++;

$worksheet1->write($row, 0, "Detailed Text File Path");
$worksheet1->write($row, 1, $detailed_text_file_path);
$row += 2;

# Headers for first sheet with formatting
my @headers1 = (
    "Test ID", "UVM Testname", "Unique Violations", "Logfile", "DV Owner",
    "DV Status (Open/ In progress/ Reviewed)", "DV Remarks", "Local Waves Path",
    "PD/Design owner", "PD/Design Status(In Progress/ Reviewed/ Fixed/Deferred))", "Design/PD comments", "DV cross review"
);

for my $col (0..$#headers1) {
    $worksheet1->write($row, $col, $headers1[$col], $header_format);
}
$row++;

# Data for first sheet
my %current_test_ids = ();  # To track current test IDs
foreach my $result (@all_results) {
    my $test_id = $result->{test_id};
    my $violation_count = scalar(@{$result->{unique_violations}});
    
    # Store current test data for comparison
    $current_test_ids{$test_id} = {
        uvm_testname => $result->{uvm_testname},
        violation_count => $violation_count
    };
    
    my $format = $data_format;
    
    # If this is a new test ID or has different violation count, highlight it
    if ($previous_file && 
        (!exists $previous_data{$test_id} || 
         $previous_data{$test_id}->{violation_count} != $violation_count)) {
        $format = $highlight_format;
    }
    
    my @row_data = (
        $test_id,
        $result->{uvm_testname},
        $violation_count,
        $result->{test_path},
        '', '', '', '', '', ''
    );
    
    for my $col (0..$#row_data) {
        $worksheet1->write($row, $col, $row_data[$col], $format);
    }
    $row++;
}

# Summary section
$row += 1;
$worksheet1->write($row, 0, "Result Summary", $bold_format);
$worksheet1->write($row, 1, "Count", $bold_format);
$row++;

# Write labels and values in separate columns with formatting
$worksheet1->write($row, 0, "Total tests", $data_format);
$worksheet1->write($row, 1, $total_tests, $data_format);
$row++;

$worksheet1->write($row, 0, "Passing tests", $data_format);
$worksheet1->write($row, 1, $total_passed_logs, $data_format);
$row++;

$worksheet1->write($row, 0, "Total logs analyzed", $data_format);
$worksheet1->write($row, 1, $total_files_analyzed, $data_format);
$row++;

$worksheet1->write($row, 0, "Total logs skipped for excluded tests", $data_format);
$worksheet1->write($row, 1, $total_skipped_logs, $data_format);
$row++;

if (@excluded_Test_IDs || @exclude_patterns) {
    $row += 1; # Add extra gap
    $worksheet1->write($row++, 0, "Master list for Test exclusions", $bold_format);
    
    # Process excluded patterns
    foreach my $pattern (@exclude_patterns) {
        my $clean_pattern = $pattern;
        $clean_pattern =~ s/^\\/|\\$//g;
        $clean_pattern =~ s/\(\?[^:]:// if $clean_pattern =~ /\(\?/;
        $clean_pattern =~ s/\)$//;
        
        if ($clean_pattern =~ /^\^/) {
            $clean_pattern =~ s/^\^//;
            $worksheet1->write($row++, 0, "$clean_pattern*", $data_format);
        }
        elsif ($clean_pattern =~ /\$$/) {
            $clean_pattern =~ s/\$$//;
            $worksheet1->write($row++, 0, "*$clean_pattern", $data_format);
        }
        else {
            $worksheet1->write($row++, 0, "*$clean_pattern*", $data_format);
        }
    }
    
    # Process exact excluded tests
    foreach my $test (@excluded_Test_IDs) {
        $worksheet1->write($row++, 0, $test, $data_format);
    }
}

# Write second worksheet
$row = 0;
$worksheet2->write($row, 0, "Report Generation timestamp");
$worksheet2->write($row, 1, $report_date);
$row++;

$worksheet2->write($row, 0, "Server");
$worksheet2->write($row, 1, $region);
$row+=2;

# Headers for second sheet
my @headers2 = (
    "Test ID", "UVM Testname", "Viol_Time", "Timing_viol_flop_path", "Logfile Path",
    "DV Owner", "DV Status (Open/ In progress/ Reviewed)", "DV Remarks", "Local WavesPath",
    "PD/Design owner", "PD/Design Status"
);

for my $col (0..$#headers2) {
    $worksheet2->write($row, $col, $headers2[$col], $header_format);
}
$row++;

# Data for second sheet and track current flop paths
my %current_flop_paths = ();
foreach my $result (@all_results) {
    foreach my $viol (@{$result->{unique_violations}}) {
        my $test_id = $result->{test_id};
        my $flop_path = $viol->{scope};
        
        # Store current flop paths for comparison
        $current_flop_paths{"$test_id:$flop_path"} = 1;
        
        my $format = $data_format;
        
        # If this is a new flop path for this test, highlight it
        if ($previous_file && 
            !exists $previous_flops{"$test_id:$flop_path"}) {
            $format = $highlight_format;
        }
        
        my @row_data = [
            $test_id,
            $result->{uvm_testname},
            $viol->{viol_time},
            $flop_path,
            $result->{test_path},
            '', '', '', '', '', ''
        ];
        
        for my $col (0..$#row_data) {
            $worksheet2->write($row, $col, $row_data[$col], $format);
        }
        $row++;
    }
}

# Create comparison worksheet if needed
if ($comparison_sheet && $previous_file) {
    $row = 0;
    
    # Write headers for comparison sheet
    $comparison_sheet->write($row, 0, "Comparison with previous run: $previous_file", $bold_format);
    $row += 2;
    
    # Section 1: New Test IDs
    $comparison_sheet->write($row++, 0, "New Test IDs with Violations", $header_format);
    $comparison_sheet->write_row($row++, 0, ["Test ID", "UVM Testname", "Unique Violations"], $header_format);
    
    my $new_tests_found = 0;
    foreach my $test_id (sort keys %current_test_ids) {
        if (!exists $previous_data{$test_id}) {
            $comparison_sheet->write($row, 0, $test_id);
            $comparison_sheet->write($row, 1, $current_test_ids{$test_id}->{uvm_testname});
            $comparison_sheet->write($row, 2, $current_test_ids{$test_id}->{violation_count});
            $row++;
            $new_tests_found = 1;
        }
    }
    
    if (!$new_tests_found) {
        $comparison_sheet->write($row++, 0, "No new test IDs found");
    }
    
    $row += 2;
    
    # Section 2: Tests with Changed Violation Counts
    $comparison_sheet->write($row++, 0, "Tests with Changed Violation Counts", $header_format);
    $comparison_sheet->write_row($row++, 0, ["Test ID", "Previous Count", "Current Count", "Difference"], $header_format);
    
    my $changed_tests_found = 0;
    foreach my $test_id (sort keys %current_test_ids) {
        if (exists $previous_data{$test_id} && 
            $previous_data{$test_id}->{violation_count} != $current_test_ids{$test_id}->{violation_count}) {
            my $prev_count = $previous_data{$test_id}->{violation_count};
            my $curr_count = $current_test_ids{$test_id}->{violation_count};
            my $diff = $curr_count - $prev_count;
            
            $comparison_sheet->write($row, 0, $test_id);
            $comparison_sheet->write($row, 1, $prev_count);
            $comparison_sheet->write($row, 2, $curr_count);
            $comparison_sheet->write($row, 3, ($diff > 0 ? "+$diff" : $diff));
            $row++;
            $changed_tests_found = 1;
        }
    }
    
    if (!$changed_tests_found) {
        $comparison_sheet->write($row++, 0, "No tests with changed violation counts found");
    }
    
    $row += 2;
    
    # Section 3: New Flop Paths
    $comparison_sheet->write($row++, 0, "New Flop Paths", $header_format);
    $comparison_sheet->write_row($row++, 0, ["Test ID", "Flop Path"], $header_format);
    
    my $new_flops_found = 0;
    foreach my $key (sort keys %current_flop_paths) {
        if (!exists $previous_flops{$key}) {
            my ($test_id, $flop_path) = split(/:/, $key, 2);
            $comparison_sheet->write($row, 0, $test_id);
            $comparison_sheet->write($row, 1, $flop_path);
            $row++;
            $new_flops_found = 1;
        }
    }
    
    if (!$new_flops_found) {
        $comparison_sheet->write($row++, 0, "No new flop paths found");
    }
}

$workbook->close();

# Write detailed text file
open(my $detail_fh, '>', $detailed_text_file_path) or die "Can't open $detailed_text_file_path: $!\n";
print $detail_fh "Timing Violations Detailed Report\n";
print $detail_fh "=" x 30, "\n\n";
print $detail_fh "Report Generated: $report_date\n";
print $detail_fh "Server: $region\n\n";

foreach my $result (@all_results) {
    print $detail_fh "Test ID: $result->{test_id}\n";
    print $detail_fh "UVM Testname: $result->{uvm_testname}\n";
    print $detail_fh "Logfile Path: $result->{test_path}\n";
    print $detail_fh "Unique Violations: " . scalar(@{$result->{unique_violations}}) . "\n\n";
    
    if (@{$result->{unique_violations}}) {
        print $detail_fh "Detailed Violations:\n";
        print $detail_fh "-" x 17, "\n";
        
        foreach my $viol (@{$result->{unique_violations}}) {
            printf $detail_fh "Time: %s, Viol_Time: %s (Line %d, # %d)\nTiming_viol_flop_path: %s\n\n",
                ($viol->{viol_time} || "Unknown"),
                ($viol->{viol_time} || "Unknown"),
                $viol->{line_num},
                $viol->{count},
                $viol->{scope};
        }
    }
    
    print $detail_fh "=" x 80, "\n\n";
}

close($detail_fh);

# Print summary
print "\nAnalysis complete!\n";
print "Excel report saved to: $excel_file\n";
print "Detailed text report saved to: $detailed_text_file_path\n\n";
print "/---------------------------------------------\n";
print "Total unique timing violations found: " . scalar(keys %unique_flops) . "\n";
print "Total tests: $total_tests\n";
print "Total passing logs: $total_passed_logs\n";
print "Total logs analyzed: $total_files_analyzed\n";
print "Total logs skipped for excluded tests: $total_skipped_logs\n";
print "/---------------------------------------------\n\n";

# Find previous Excel file in the same directory for comparison
sub find_previous_excel_file {
    my ($dir, $current_timestamp) = @_;
    
    # Get all Excel files matching the pattern
    my @files = glob("$dir/timing_violations_*.xlsx");
    
    # Sort files by modification time (newest first)
    @files = sort { (stat($b))[9] <=> (stat($a))[9] } @files;
    
    # Return the most recent file that isn't the current one
    foreach my $file (@files) {
        if ($file !~ /$current_timestamp/) {
            return $file;
        }
    }
    
    return undef;
}

# Load data from previous Excel file for comparison
sub load_previous_excel_data {
    my ($file) = @_;
    my %test_data = ();  # For Sheet 1 data
    my %flop_data = ();  # For Sheet 2 data
    
    eval {
        my $parser = Spreadsheet::ParseExcel->new();
        my $workbook = $parser->parse($file);
        
        die "Failed to open Excel file: $file" unless defined $workbook;
        
        # Process Sheet 1 for test IDs and violation counts
        if (my $sheet = $workbook->worksheet(0)) {
            my ($row_min, $row_max) = $sheet->row_range();
            my ($col_min, $col_max) = $sheet->col_range();
            
            # Find the row where data starts (after headers)
            my $data_start_row = 0;
            for my $row ($row_min..$row_max) {
                my $cell = $sheet->get_cell($row, 0);
                if ($cell && $cell->value() eq "Test ID") {
                    $data_start_row = $row + 1;
                    last;
                }
            }
            
            # Collect test ID and violation count data
            for my $row ($data_start_row..$row_max) {
                my $test_id_cell = $sheet->get_cell($row, 0);
                my $uvm_test_cell = $sheet->get_cell($row, 1);
                my $viol_count_cell = $sheet->get_cell($row, 2);
                
                next unless $test_id_cell && $viol_count_cell;
                
                my $test_id = $test_id_cell->value();
                my $uvm_testname = $uvm_test_cell ? $uvm_test_cell->value() : '';
                my $viol_count = $viol_count_cell->value();
                
                next unless $test_id && $test_id !~ /^Result Summary$/;
                
                $test_data{$test_id} = {
                    uvm_testname => $uvm_testname,
                    violation_count => $viol_count
                };
            }
        }
        
        # Process Sheet 2 for flop paths
        if (my $sheet = $workbook->worksheet(1)) {
            my ($row_min, $row_max) = $sheet->row_range();
            my ($col_min, $col_max) = $sheet->col_range();
            
            # Find the row where data starts (after headers)
            my $data_start_row = 0;
            for my $row ($row_min..$row_max) {
                my $cell = $sheet->get_cell($row, 0);
                if ($cell && $cell->value() eq "Test ID") {
                    $data_start_row = $row + 1;
                    last;
                }
            }
            
            # Collect test ID and flop path combinations
            for my $row ($data_start_row..$row_max) {
                my $test_id_cell = $sheet->get_cell($row, 0);
                my $flop_path_cell = $sheet->get_cell($row, 3);  # Column D contains flop paths
                
                next unless $test_id_cell && $flop_path_cell;
                
                my $test_id = $test_id_cell->value();
                my $flop_path = $flop_path_cell->value();
                
                next unless $test_id && $flop_path;
                
                $flop_data{"$test_id:$flop_path"} = 1;
            }
        }
    };
    
    if ($@) {
        warn "Error reading previous Excel file: $@";
        # Return empty hashes if there was an error
        return (), ();
    }
    
    return %test_data, %flop_data;
}