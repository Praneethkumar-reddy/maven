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
use Excel::Writer::XLSX; # Added for Excel support

my ($netlist_ver, $corner, $list, $help);
my $timestamp = strftime("%Y%m%d%H%M%S", localtime);
my $month_abbr = strftime("%b", localtime);
my $date = strftime("%d", localtime);

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
my @valid_lists = qw(hp sanity hp_io);
if (defined $list && !grep { $_ eq $list } @valid_lists) {
    print "ERROR: Invalid list type '$list'. Valid values are: " . join(", ", @valid_lists) . "\n\n";
    die print_help();
}

# Create the base directory structure
my $base_dir = "/scratchV/eagle_sdf_timing_violations_check/eagle_chiptop";
my $target_dir = "${base_dir}/${netlist_ver}_${corner}";
my $result_dir = "${target_dir}/${list}";

make_path($result_dir) or die "Failed to create directory: $result_dir\n";

# Output files with timestamp
my $excel_file = "${result_dir}/timing_violations_${timestamp}.xlsx";
my $detailed_text_file = "${result_dir}/timing_violations_detail_${timestamp}.txt";

# Sheet names
my $sheet1_name = "${list}_${netlist_ver}_${corner}_${date}${month_abbr}";
my $sheet2_name = "${list}_${netlist_ver}_${corner}_${date}${month_abbr}_D";

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

#-----------------------------------------------------------------
# Configuration and data structures
#-----------------------------------------------------------------

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
                        qr/on_the_fly_porstn/, qr/porstn_es0_es1_regs_chk$/, qr/warm_rst/, qr/on_the_fly_sw_rst/, 
                        qr/exptmst0_onff/, qr/onoff/, qr/^efuse_stop/, qr/^efuse_stby/);

# Exact Tests to exclude: These are specific test IDs that need to be excluded.
my @excluded_Test_IDs = qw(mhu27 ewic1 firewall17 design_sanity15 design_sanity17 camera71 mipidsi6 cdc23 lp_ymn_hscmp 
                          efuse_itcm efuse_hp_boot efuse_lp_boot efuse_rd_ocvm efuse_rd_cvm efuse_v18encheck design_sanity2 
                          design_sanity3 design_sanity5 design_sanity6 design_sanity8 design_sanity9 fullchip_on_the_fly_epor_poresetn_pin 
                          host_sys_sw_rst_regs_chk zaphod_hard_reset design_sanity0 i3c_on_off chip_debug6 chip_debug15 wounding_11 
                          design_sanity1 design_sanity4 eth_rmii_rx_systop_pwr_on_off LPUART_32Byt_TxRx_921600Kbps_PowOnOff_LPYAMIN_LPDTCM_GPIOA 
                          es0_es1_porstn_regs_chk es0_es1_porstn_btwn_local_cpu_internal_tcm_xfers wounding_16 expmst0_gpiox_pwr_on_off 
                          wounding_18 jpeg01 dave14 LPI2C_Pow_On_Off_LPYmn_GPIOA lpcmp_upf_irq_test1 usb21 sdc_pwr_on_off);

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
my $total_files_analyzed = 0;
my $total_passed_logs = 0;
my $total_skipped_logs = 0;
my @excluded_test_ids;

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
            
            if (my $scope_line = <$line_fh>) {
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

# Process each directory
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
                $total_passed_logs++; # <- Count all logs that pass the keywords
                
                if ($content =~ /-test_id\s+(\S+)/) {
                    my $test_id = $1;
                    
                    if (is_excluded($test_id)) {
                        print "Excluding $_ because test_id '$test_id' matches exclude criteria.\n";
                        push @excluded_test_ids, $test_id;
                        $total_skipped_logs++;
                        return;
                    }
                }
                
                # Process the log file and collect results
                process_log_file($File::Find::name);
                $total_files_analyzed++;
            }
        },
        $directory
    );
}

if (@files_without_reset) {
    print "\nSummary of files without 'CHIP POR RESET IS RELEASED':\n";
    print "=" x 50, "\n";
    
    foreach my $file (@files_without_reset) {
        my $test_name = basename(dirname($file));
        printf "%-40s : %s\n", $test_name, $file;
    }
    
    print "\nTotal files without CHIP POR RESET IS RELEASE: " . scalar(@files_without_reset) . "\n";
    print "=" x 50, "\n";
}

# Create Excel file directly from the collected data
if (@all_results) {
    # Initialize the Excel workbook
    my $workbook = Excel::Writer::XLSX->new($excel_file) or die "Could not create Excel file $excel_file: $!\n";
    
    # Create first worksheet
    my $worksheet1 = $workbook->add_worksheet($sheet1_name);
    
    # Write headers and data for the first sheet
    my $row = 0;
    $worksheet1->write($row++, 0, "Report Generation timestamp");
    $worksheet1->write($row-1, 1, $report_date);
    
    $worksheet1->write($row++, 0, "Server");
    $worksheet1->write($row-1, 1, $region);
    
    $worksheet1->write($row++, 0, "Regression Directory");
    $worksheet1->write($row-1, 1, join(" ", @regression_directories));
    
    $worksheet1->write($row++, 0, "Detailed Text File Path");
    $worksheet1->write($row-1, 1, $detailed_text_file);
    
    $row++; # Add empty row
    
    # Write headers
    my @headers = ("Test ID", "UVM Testname", "Unique Violations", "Logfile", "DV Owner", 
                  "DV Status (Open/ In progress/ Reviewed)", "DV Remarks", "Local Waves Path", 
                  "PD/Design owner", "PD/Design Status(In Progress/ Reviewed/ Fixed/ Deffered)", 
                  "Design/PD comments", "DV cross review");
    
    # Write column headers
    for (my $col = 0; $col < scalar(@headers); $col++) {
        $worksheet1->write($row, $col, $headers[$col]);
    }
    $row++;
    
    # Write data rows
    foreach my $result (@all_results) {
        my @row_data = (
            $result->{test_id},
            $result->{uvm_testname},
            scalar(@{$result->{unique_violations}}),
            $result->{test_path},
            "", "", "", "", "", "", ""
        );
        
        for (my $col = 0; $col < scalar(@row_data); $col++) {
            $worksheet1->write($row, $col, $row_data[$col]);
        }
        $row++;
    }
    
    $row += 2; # Add empty rows
    
    # Write summary
    $worksheet1->write($row++, 0, "Result Summary");
    $worksheet1->write($row-1, 1, "Count");
    
    $worksheet1->write($row++, 0, "Passing tests");
    $worksheet1->write($row-1, 1, $total_passed_logs);
    
    $worksheet1->write($row++, 0, "Total logs analyzed");
    $worksheet1->write($row-1, 1, $total_files_analyzed);
    
    $worksheet1->write($row++, 0, "Total logs skipped for excluded tests");
    $worksheet1->write($row-1, 1, $total_skipped_logs);
    
    $row += 2; # Add empty rows
    
    # Add excluded tests list if applicable
    if (@excluded_test_ids || @exclude_patterns) {
        $worksheet1->write($row++, 0, "Master list for Test exclusions");
        
        # Process exclude patterns with proper formatting
        foreach my $pattern (@exclude_patterns) {
            my $clean_pattern = $pattern;
            
            # Remove forward slashes at start and end
            $clean_pattern =~ s/^\\/|\\/\$//g;
            
            # Remove regex syntax markers
            $clean_pattern =~ s/\(?[\^:]://; # Remove (?^: or (?:
            $clean_pattern =~ s/\)\$//; # Remove trailing )
            
            # Add wildcard (*) if pattern had start/end anchors
            if ($clean_pattern =~ /^\^/) {
                $clean_pattern =~ s/^\^//;
                $worksheet1->write($row++, 0, "$clean_pattern*");
            }
            elsif ($clean_pattern =~ /\$/) {
                $clean_pattern =~ s/\$//;
                $worksheet1->write($row++, 0, "*$clean_pattern");
            }
            else {
                $worksheet1->write($row++, 0, "*$clean_pattern*");
            }
        }
        
        # Process exact excluded tests
        foreach my $test (@excluded_test_ids) {
            $worksheet1->write($row++, 0, $test);
        }
    }
    
    # Create second worksheet
    my $worksheet2 = $workbook->add_worksheet($sheet2_name);
    
    # Write headers and data for the second sheet
    $row = 0;
    $worksheet2->write($row++, 0, "Report Generated:");
    $worksheet2->write($row-1, 1, $report_date);
    
    $worksheet2->write($row++, 0, "Server:");
    $worksheet2->write($row-1, 1, $region);
    
    $row++; # Add empty row
    
    # Write headers
    my @detail_headers = ("Test ID", "UVM Testname", "Viol_Time", "Timing_viol_flop_path", "Logfile Path", 
                         "DV Owner", "DV Status (Open/ In progress/ Reviewed)", "DV Remarks", "Local WavesPath", 
                         "PD/Design owner", "PD/Design Status(In Progress/ Reviewed/ Fixed)", "Review comments");
    
    # Write column headers
    for (my $col = 0; $col < scalar(@detail_headers); $col++) {
        $worksheet2->write($row, $col, $detail_headers[$col]);
    }
    $row++;
    
    # Write detailed violations data
    foreach my $result (@all_results) {
        foreach my $viol (@{$result->{unique_violations}}) {
            my @row_data = (
                $result->{test_id},
                $result->{uvm_testname},
                $viol->{viol_time},
                $viol->{scope},
                $result->{test_path},
                "", "", "", "", "", ""
            );
            
            for (my $col = 0; $col < scalar(@row_data); $col++) {
                $worksheet2->write($row, $col, $row_data[$col]);
            }
            $row++;
        }
    }
    
    # Close the Excel workbook
    $workbook->close();
    
    # Create the detailed text file
    open(my $detail_fh, '>', $detailed_text_file) or die "Can't open $detailed_text_file: $!\n";
    
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
    
    print "\nAnalysis complete!\n";
    print "Excel report saved to: $excel_file\n";
    print "Detailed text report saved to: $detailed_text_file\n\n";
} else {
    print "No patterns found in any log files.\n\n";
}

print "/-----------------------------------\n";
print "Total unique timing violations found: " . scalar(keys %unique_flops) . "\n";
print "Total passing logs: $total_passed_logs\n";
print "Total logs analyzed: $total_files_analyzed\n";
print "Total logs skipped for excluded tests: $total_skipped_logs\n";
print "/-----------------------------------\n\n";

# Help subroutine for the script
sub print_help {
    my $help_text = "===================== Timing Violations Check help =====================\n";
    $help_text .= "This script analyzes log files for timing violations after chip reset\n\n";
    $help_text .= "Required arguments:\n";
    $help_text .= "\t -netlist_ver <ver> : Specify netlist version\n";
    $help_text .= "\t -corner <corner> : Specify corner for analysis (TYP_MAX, TYP_MIN, MAXMAX, MINMIN)\n";
    $help_text .= "\t -list <type> : Specify list type (hp, sanity, hp_io)\n\n";
    $help_text .= "Optional arguments:\n";
    $help_text .= "\t -help, -h : Display this help message\n\n";
    $help_text .= "Additional directories to analyze can be passed as arguments after the options\n";
    $help_text .= "Example usage:\n";
    $help_text .= "\t perl $0 -netlist_ver 3P0_050825_TO -corner TYP_MAX -list hp /path/to/logs\n";
    $help_text .= "=================================================================\n";
    
    return $help_text;
}
