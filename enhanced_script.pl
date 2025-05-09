#!/usr/bin/perl

use strict;
use warnings;
use File::Find;
use Cwd;
use File::Basename;

################################################################################
# Usage: script.pl <output_file> <directory1> [<directory2> ...]
################################################################################

die "Usage: $0 <output_file> <directory1> [<directory2> ...]\n"
unless @ARGV >= 2;

#--------------------------------------------------------------------------
# Command-line arguments
#--------------------------------------------------------------------------
my $output_file = shift @ARGV;
my @directories = @ARGV;

#--------------------------------------------------------------------------
# Configuration and data structures
#--------------------------------------------------------------------------
my $specific_file_pattern = 'local_log.log';
my @keywords = (
    'UVM_WARNING : 0',
    'UVM_ERROR : 0',
    'UVM_FATAL : 0'
);

# List of patterns to exclude - can now contain both exact matches and wildcard patterns
my @exclude_patterns = (
    'soc_lp_upf',
    'stby_stop',
    'fast_gpio',
    'wounding_lp',
    'reset_upf',
    'design_sanity2',
    'design_sanity3',
    'design_sanity5',
    'design_sanity6',
    'design_sanity8',
    'design_sanity9',
    'es0_es1_porstn_regs_chk',
    'on_the_fly_porstn',
    'porstn_es0_es1_regs_chk',
    'es0_es1_porstn_btwn_local_cpu_internal_tcm_xfers',
    'warm_rst',
    'chip_debug6',
    'chip_debug15',
    'wounding_11',
    'lp_ymn_hscmp',
    'efuse_rd_ocvm',
    'efuse_stop',
    'efuse_lp_boot',
    'efuse_stby',
    'ewic1',
    'mhu27',
    'design_sanity1',
    'design_sanity4',
    'efuse_hp_boot',
    'on_the_fly_sw_rst',
    'wounding_16',
    'expmst0_gpiox_pwr_on_off',
    'efuse_v18encheck',
    'efuse_itcm',
    'efuse_rd_cvm',
    'wounding_18',
    'jpeg01',
    'dave14',
    'oob9',
    'exptmst0_onff',
    'usb21',
    'lpcmp_upf_irq_test1',
    'onoff',
    'LPI2C_Pow_On_Off_LPYmn_GPIO',
    'sdc_pwr_on_off',
    'eth_rmii_rx_systop_pwr_on_off',
    'uart0_exptmst0_onff',
    'LPUART_32Byt_TxRx_921600Kbps_PowOnOff_LPYAMIN_LPDTCM_GPIOA',
    'fullchip_on_the_fly_epor_poresetn_pin',
    'host_sys_sw_rst_regs_chk',
    'zaphod_hard_reset',
    'design_sanity15',
    'design_sanity17',
    'efuse_stop0',
    'efuse_stop3',
    'efuse_stby1',
    'efuse_stby3',
    'firewall17',
    'camer71',
    'mipidsi6',
    'cdc23',
    'design_sanity0',
    'i3c_on_off'
);

# Enhanced matching function to handle both wildcard patterns and exact strings
# We'll split the exclude patterns into two categories:
my @exact_patterns = grep { $_ !~ /\*/ } @exclude_patterns;
my @wildcard_patterns = grep { $_ =~ /\*/ } @exclude_patterns;

# Convert wildcard patterns to regex patterns
my @regex_patterns = map { 
    my $pattern = $_;
    $pattern =~ s/\*/.*/g;  # Convert * to .*
    qr/^$pattern$/;         # Anchor to match exactly
} @wildcard_patterns;

my @all_results;
my %unique_flops;
my $count = 1;
my @files_without_reset;
my $total_files_processed = 0;
my $total_passed_logs = 0; # <- New counter for all logs that match keywords
my @excluded_test_ids;

# Function to check if a test_id should be excluded
sub should_exclude_test_id {
    my $test_id = shift;
    
    # Check exact matches first
    foreach my $pattern (@exact_patterns) {
        if ($test_id eq $pattern) {
            return 1;
        }
    }
    
    # Check wildcard patterns
    foreach my $regex (@regex_patterns) {
        if ($test_id =~ $regex) {
            return 1;
        }
    }
    
    return 0;
}

sub escape_csv {
    my $field = shift;
    return '' unless defined $field;
    if ($field =~ /[,"\r\n]/) {
        $field =~ s/"/""/g;
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

open(my $out_fh, '>', $output_file) or die "Can't open file $output_file: $!\n";

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
                    
                    if (should_exclude_test_id($test_id)) {
                        print "Excluding $_ because test_id '$test_id' matches exclude pattern.\n";
                        push @excluded_test_ids, $test_id;
                        return;
                    }
                }
                
                print $out_fh "$File::Find::name\n";
                process_log_file($File::Find::name);
                $total_files_processed++;
            }
        },
        $directory
    );
}

close($out_fh);

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

if (@all_results) {
    open(my $csv_fh, '>', 'timing_violations.csv') or die "Can't open timing_violations.csv: $!\n";
    print $csv_fh "Test ID,UVM Testname,Unique Violations,Logfile,DV Owner,DV Status (Open/ In progress/ Reviewed),DV Remarks,Local Waves Path,PD/Design owner,PD/Design Status(In Progress/ Reviewed/ Fixed),Review comments\n";
    
    foreach my $result (@all_results) {
        print $csv_fh join(',',
            map { escape_csv($_) } (
                $result->{test_id},
                $result->{uvm_testname},
                scalar(@{$result->{unique_violations}}),
                $result->{test_path},
                '', '', '', '', '', ''
            )
        ), "\n";
    }
    
    if (@excluded_test_ids) {
        print $csv_fh "\n\n";
        print $csv_fh "Excluded tests(Confirmed by the owners)\n";
        print $csv_fh "$_\n" for @excluded_test_ids;
    }
    
    close($csv_fh);
    
    open(my $detail_csv_fh, '>', 'timing_violations_detail.csv') or die "Can't open timing_violations_detail.csv: $!\n";
    print $detail_csv_fh "Test ID,UVM Testname,Viol_Time,Timing_viol_flop_path,Logfile Path,DV Owner,DV Status (Open/ In progress/ Reviewed),DV Remarks,Local Waves Path,PD/Design owner,PD/Design Status(In Progress/ Reviewed/ Fixed) ,Review comments\n";
    
    foreach my $result (@all_results) {
        foreach my $viol (@{$result->{unique_violations}}) {
            print $detail_csv_fh join(',',
                map { escape_csv($_) } (
                    $result->{test_id},
                    $result->{uvm_testname},
                    $viol->{viol_time},
                    $viol->{scope},
                    $result->{test_path},
                    '', '', '', '', '', ''
                )
            ), "\n";
        }
    }
    
    close($detail_csv_fh);
    
    open(my $detail_fh, '>', 'timing_violations_detail.txt') or die "Can't open timing_violations_detail.txt: $!\n";
    print $detail_fh "Timing Violations Detailed Report\n";
    print $detail_fh "=" x 30, "\n\n";
    
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
    print "Summary CSV report saved to: timing_violations.csv\n";
    print "Detailed CSV report saved to: timing_violations_detail.csv\n";
    print "Detailed text report saved to: timing_violations_detail.txt\n";
    print "Total unique timing violations found: " . scalar(keys %unique_flops) . "\n";
} else {
    print "No patterns found in any log files.\n";
}

print "\nTotal log files processed: $total_files_processed\n";
print "Total passed logs count: $total_passed_logs\n";
