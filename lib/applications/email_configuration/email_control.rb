#!/usr/bin/env ruby
# This file is a test for the alarm sound
#   # by calling a separate process in Ruby and 
#   # keeping track of the PID to kill it whenever
#   # necessary.

options = {
    :log_output => true
}
email_script = File.join( File.expand_path( File.dirname( __FILE__ ) ), "email_script.py" )
Daemons.run(email_script, options)
