# This file contains a class used to determine whether to raise an alarm

module Applications
    # This script will control the alarm service
    SOUND_CONTROL_FILE = File.join( File.expand_path( File.dirname(__FILE__) ), 'sound_files', 'sound_control.rb' )
    
    class Alarm
        # initialize
        # Description:  Initialize an Alarm class instance
        # Inputs:       db_client => pass the connection to the MySQL database to avoid recreating connections
        #               send_help => Option used by Alexa to immediately send an emergency notification
        # Outputs:      Creates a class instance
        def initialize( db_client, send_help=false, sensor_check=false )
            # Sending db_client across classes
            @db_client = db_client
            determine_alarm( send_help, sensor_check )
        end

        private
                
        # determine_alarm
        # Description:  Turn on or off the external alarm speaker based on values in 
        #               mostly the database table 'sensor_status"
        # Inputs:       send_help => boolean to add "alexa" as an alarm sensor
        # Outputs:      None
        def determine_alarm( send_help, sensor_check )
            alarm_sensors = []
            disconnected_sensors = []
            # This ensures a ONE-TIME alarm start
            if send_help
                alarm_sensors = ["alexa"]
            else
                # Long way to determine alarm
                # Get the status of all sensors from the database
                # Get the function of all sensors from the database
                # Logic to determine if alarm should be on or not
                current_sensor_status = get_sensor_statuses
                current_sensor_status.each do |sensor|
                    #TODO need to add proximity code here
                    # IF Sensor is ENABLED AND Sensor is NOT 0 AND Sensor is not in a dismissed state
                    if (sensor["enabled"] == 1) && (sensor["status"] != 0) && (sensor["dismiss"] == 0)
                        alarm_sensors << sensor["type"]
                    end
                    if sensor_check && sensor["verbose"] == "disconnected"
                        disconnected_sensors << sensor["type"]
                    end
                end
            end
            if alarm_sensors.empty?
                turn_off_speaker
            else
                Notification.new( @db_client, alarm_sensors )
                only_door_alarm = ( alarm_sensors.size == 1 && alarm_sensors.first == "door" )
                if only_door_alarm && !currently_leaving
                    log_event( alarm_sensors, disconnected_sensors ) if !Applications.alarm_on?
                    turn_on_speaker( only_door_alarm )
                elsif !only_door_alarm # Don't care whether you are leaving or not if there are multiple sensors in alarm state
                    log_event( alarm_sensors, disconnected_sensors ) if !Applications.alarm_on?
                    turn_on_speaker
                end
            end
        end # determine_alarm
        
        # currently_leaving
        # Description:  Determine if the user has just issued a command to Alexa that
        #               they will be opening the door soon. (<60s)
        # Inputs:       None
        # Outputs:      Boolean
        def currently_leaving
            # This only gets set by the door sensor in the 'alexa' table
            response = @db_client.query( "SELECT TIMESTAMPDIFF(SECOND,updated_time,CURRENT_TIMESTAMP()) AS time_diff, mode FROM #{ALEXA_INFORMATION}" )
            if response.first["time_diff"] < 60 && response.first["mode"] == "leaving"
                return true
            end
            # If after the 60 seconds, set status to "left" to indicate that the user has been gone for more than 60 seconds
            @db_client.query( "UPDATE #{ALEXA_INFORMATION} SET mode='left'" )
            return false
        end # currently_leaving

        # get_sensor_statuses
        # Description:  Perform a mySQL query to get all of the sensor status data
        # Inputs:       None
        # Outputs:      Array of sensor status rows
        def get_sensor_statuses
            response = @db_client.query( "SELECT name,status,updated_time,enabled,type,dismiss,verbose FROM #{SENSOR_STATUS}" )
            return response.entries
        end # get_sensor_statuses
        
        # log_event
        # Description:  Whenever a sensor is in an alarm state, this needs to be 
        #               logged to the database, so the user can look up a history
        #               of past events
        # Inputs:       A list of sensors that are in an alarm state
        # Outputs:      None
        def log_event( sensor_list, disconnected_sensors )
            disconnected_sensors.each do |sensor|
                description = "The hub has not received a signal from this sensor in over 15 minutes"
                @db_client.query( "INSERT INTO #{EVENT_LOG} (type, name, description) VALUES ('#{sensor}', '#{sensor}', '#{description}')" ) 
            end
            sensor_list.each do |sensor|
                description = "No description available for this sensor"
                case sensor
                when "door"
                    description = "Door opened"
                when "wndw"
                    description = "Window was opened from outside"
                when "smco"
                    description = "Smoke alarm detected some smoke"
                end
                @db_client.query( "INSERT INTO #{EVENT_LOG} (type, name, description) VALUES ('#{sensor}', '#{sensor}', '#{description}')" )
            end
        end # log_event
        
        # turn_off_speaker
        # Description:  This method turns the speaker off (if currently on)
        # Inputs:       None
        # Outputs:      None
        def turn_off_speaker
            puts "SPEAKER OFF"
            # The daemons gem will handle the stopping of the 
            #   # audio file playing process
            #if File.exist?( ALARM_FILE )
            if Applications.alarm_on?
                `#{SOUND_CONTROL_FILE} stop`
                # Delete file to show that the alarm is on
                #File.delete( ALARM_FILE )
                Applications.alarm_off
            end
        end # turn_off_speaker
        
        # turn_on_speaker
        # Description:  This method turns the speaker on (if currently off)
        #               The speaker plays a continous sound until it is interrupted
        # Inputs:       delay => boolean of whether to wait 30 seconds. This is for the
        #                   case of the door sensor only
        # Outputs:      None
        def turn_on_speaker( delay=false )
            puts "SPEAKER ON"
            # The daemons gem will handle the starting of the 
            #   # audio file playing process
            # Call the ruby script
            #TODO If already running, the script returns an error internally,
            #   # you should clean this up!
            #if !File.exist?( ALARM_FILE )
            if !Applications.alarm_on?
                if delay
                    # call the sound_control file with delay argument
                    `#{SOUND_CONTROL_FILE} start -- delay` 
                else
                    `#{SOUND_CONTROL_FILE} start`
                end
                # Create a new file to show that the alarm is on
                #File.open(ALARM_FILE, "w") {}
                Applications.alarm_on
            end
        end # turn_on_speaker
    end # class Alarm
end # module Applications
