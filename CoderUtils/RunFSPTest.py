import os
import shutil
import yaml
import subprocess
import time
import argparse

"""
Install dependencies:
> pip install PyYAML
"""

# default parameters
JLINK_PATH = r"/home/coder/workspace/JLink_Linux_V966_x86_64/JLinkExe"
RTT_LOGGER_PATH = r"/home/coder/workspace/JLink_Linux_V966_x86_64/JLinkRTTLoggerExe"
PATH_TEST_INFO = r"build/r_ospi_b/ra8m2_ek/gcc/test_info.yml"
PATH_JLINK_SCRIPT = "CuzJFlash.jlink"
PATH_JLINK_LOG = "RTT_Viewer.log"
PATH_JLINK_LOG_ACC = "RTT_Viewer_All.log"
DEVICE_PART_NUMBER = "R7KA8M2JF_CPU0"
DEVICE_IP = "127.0.0.1:19020"
LOGGER_TIMEOUT_SEC = 60
RUN_SPECIFIED_BUILD = ""
LOG_DIR_PATH = r"./.JLinkLogPath"

"""
/*
 * @brief Parses YAML config, generates J-Link script, flashes device and retrieves RTT logs.
 *        Also parses log content at runtime to generate a summary list of test results.
 * @param info_path Path to the YAML configuration file.
 * @param script_path Path to generate the J-Link script file.
 * @param log_path Path to store the RTT log output.
 * @param log_acc_path Path to store the accumulated RTT logs.
 * @param part_number Target MCU part number.
 * @param ip Device IP address, can be empty.
 * @param log_dir_path Path to the directory where individual build logs will be saved.
 */
"""
def execute_jlink_workflow(info_path, script_path, log_path, log_acc_path, part_number, ip, log_dir_path):
    # Check if log directory exists to clean up old logs
    if os.path.exists(log_dir_path):
        shutil.rmtree(log_dir_path)
        
    os.makedirs(log_dir_path)

    # Check if individual log file exists
    if os.path.exists(log_path):
        os.remove(log_path)
        
    # Check if accumulated log file exists
    if os.path.exists(log_acc_path):
        os.remove(log_acc_path)

    summary_list = []

    # Open YAML file for reading
    with open(info_path, 'r') as file:
        data = yaml.safe_load(file)

    # Check if YAML data is valid
    if not data:
        # Exit function if YAML is empty
        return

    # Iterate through all top-level categories
    for category_name, category_data in data.items():
        # Check if category data is a dictionary
        if not isinstance(category_data, dict):
            # Skip to next category on invalid structure
            continue
            
        # Iterate through each project configuration
        for config_name, config_data in category_data.items():
            projects = config_data.get('projects', [])

            # Check if projects list is empty
            if not projects:
                # Skip to next configuration if no projects
                continue

            app_path = projects[0].get('application', '')
            dependencies = projects[0].get('dependencies', [])
            rtt_addr_raw = str(projects[0].get('rtt_address', ''))
            
            # Check if a specific build is requested and does not match the current app
            if RUN_SPECIFIED_BUILD and (RUN_SPECIFIED_BUILD != app_path):
                # Skip to next configuration as it does not match the specified build
                continue

            # Check if RTT address is valid and starts with hex prefix
            if rtt_addr_raw and not rtt_addr_raw.startswith('0x'):
                rtt_addr = f"0x{rtt_addr_raw}"
            else:
                rtt_addr = rtt_addr_raw

            flash_log_file = os.path.join(log_dir_path, f"{config_name}_flash.log")
            exec_log_file = os.path.join(log_dir_path, f"{config_name}_exec.log")

            # Open J-Link script file for writing
            with open(script_path, 'w') as script_file:
                # Check if there are dependencies to load
                if dependencies:
                    # Iterate through dependencies
                    for dep in dependencies:
                        script_file.write(f"loadfile {dep}\n")
                        
                script_file.write(f"loadfile {app_path}\n")
                script_file.write("r\n")
                script_file.write("g\n")
                script_file.write("q\n")

            flash_cmd = [JLINK_PATH]

            # Append IP argument if provided
            if ip:
                flash_cmd.extend(["-ip", ip])

            flash_cmd.extend([
                "-device", part_number,
                "-if", "SWD",
                "-speed", "4000",
                "-autoconnect", "1",
                "-CommanderScript", script_path
            ])
            
            print(f"\n\n\n============================================================")
            print(f"--- Flashing device for [{category_name}] {config_name} ---")
            
            # Open flash log file for writing stdout and stderr
            with open(flash_log_file, 'w') as flash_out:
                subprocess.run(flash_cmd, stdout=flash_out, stderr=subprocess.STDOUT)

            log_cmd = [RTT_LOGGER_PATH]

            # Append IP argument if provided for logger
            if ip:
                log_cmd.extend(["-ip", ip])

            # Configure logger command explicitly ensuring RTTAddress is correct
            log_cmd.extend([
                "-device", part_number,
                "-if", "SWD",
                "-speed", "4000"
            ])
            
            # Check if RTT address is provided before appending
            if rtt_addr:
                log_cmd.extend(["-RTTAddress", rtt_addr])
                
            log_cmd.extend([
                "-RTTChannel", "0",
                log_path
            ])

            print(f"--- Starting execution for [{category_name}] {config_name} ---")
            print(f"============================================================\n")
            
            logger_process = subprocess.Popen(log_cmd)
            start_time = time.time()
            
            last_pos = 0
            current_log = ""
            timeout_occurred = False

            # Loop to monitor log file in real-time
            while True:
                # Check if elapsed time exceeds timeout
                if (time.time() - start_time) > LOGGER_TIMEOUT_SEC:
                    print(f"\n[TIMEOUT] Execution exceeded {LOGGER_TIMEOUT_SEC} seconds. Terminating RTT Logger...\n")
                    logger_process.terminate()
                    timeout_occurred = True
                    # Break loop due to timeout
                    break
                
                # Check if log path exists
                if os.path.exists(log_path):
                    # Try to read the file safely
                    try:
                        # Open log file for reading
                        with open(log_path, 'r') as log_file:
                            log_file.seek(last_pos)
                            new_data = log_file.read()
                            last_pos = log_file.tell()
                            
                            # Check if new data was read
                            if new_data:
                                print(new_data, end='', flush=True)
                                current_log += new_data
                                
                        # Check for completion string
                        if "FSP TESTS ALLDONE" in current_log:
                            # Allow a tiny delay to ensure all logs flush before killing process
                            time.sleep(0.5)
                            logger_process.terminate()
                            # Break loop when tests complete
                            break
                    except Exception:
                        # Skip exception handling
                        pass
                
                time.sleep(0.5)

            logger_process.wait()

            # Check if log file exists for final read to catch remaining output
            if os.path.exists(log_path):
                # Try to read the final content
                try:
                    # Open log file for final reading
                    with open(log_path, 'r') as log_file:
                        log_file.seek(last_pos)
                        new_data = log_file.read()
                        
                        # Check if final new data is available
                        if new_data:
                            print(new_data, end='', flush=True)
                            current_log += new_data
                except Exception:
                    # Skip exception handling
                    pass
                
                # Open exec log file for writing execution data
                with open(exec_log_file, 'w') as exec_out:
                    exec_out.write(current_log)

                # Check if timeout occurred to append special note
                if timeout_occurred:
                    summary_line = "TEST TIMED OUT"
                else:
                    summary_line = "No test summary found"
                    
                lines = current_log.split('\n')
                
                # Iterate through log lines to find metrics
                for line in lines:
                    # Check if line contains test metrics pattern
                    if "Tests" in line and "Failures" in line and "Ignored" in line:
                        summary_line = line.strip()
                        # Break loop once summary is found
                        break
                        
                summary_list.append(f"{summary_line} | BUILD: {app_path} | CATEGORY: {category_name}")
                
                # Open accumulated log file to append
                with open(log_acc_path, 'a') as acc_log_file:
                    acc_log_file.write(f"###################### Flash Info: SREC={app_path} | RTTAddress={rtt_addr_raw} | Category={category_name} ######################\n")
                    acc_log_file.write(current_log)
                    acc_log_file.write("\n\n")
                
                os.remove(log_path)
                
    # Check if summary list contains items
    if summary_list:
        print("\n###################### FINAL TEST SUMMARY LIST ######################")
        # Iterate through summary items
        for item in summary_list:
            print(item)
        print("#####################################################################\n")

    # Return successfully
    return

# Check if executed as main script
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run FSP Tests with override parameters.")
    
    parser.add_argument("-JLINK_PATH", type=str, default=JLINK_PATH, help="Path to JLink executable")
    parser.add_argument("-RTT_LOGGER_PATH", type=str, default=RTT_LOGGER_PATH, help="Path to JLink RTT Logger")
    parser.add_argument("-PATH_TEST_INFO", type=str, default=PATH_TEST_INFO, help="Path to test info YAML config")
    parser.add_argument("-PATH_JLINK_SCRIPT", type=str, default=PATH_JLINK_SCRIPT, help="Path to generate JLink script")
    parser.add_argument("-PATH_JLINK_LOG", type=str, default=PATH_JLINK_LOG, help="Path to RTT log output")
    parser.add_argument("-PATH_JLINK_LOG_ACC", type=str, default=PATH_JLINK_LOG_ACC, help="Path to accumulated log")
    parser.add_argument("-DEVICE_PART_NUMBER", type=str, default=DEVICE_PART_NUMBER, help="Target MCU part number")
    parser.add_argument("-DEVICE_IP", type=str, default=DEVICE_IP, help="Device IP address")
    parser.add_argument("-LOGGER_TIMEOUT_SEC", type=int, default=LOGGER_TIMEOUT_SEC, help="Logger timeout in seconds")
    parser.add_argument("-RUN_SPECIFIED_BUILD", type=str, default=RUN_SPECIFIED_BUILD, help="Specify exact app_path to flash and test")
    parser.add_argument("-LOG_DIR_PATH", type=str, default=LOG_DIR_PATH, help="Directory to store individual build logs")
    
    args = parser.parse_args()

    # Override variables in global scope directly
    JLINK_PATH = args.JLINK_PATH
    RTT_LOGGER_PATH = args.RTT_LOGGER_PATH
    LOGGER_TIMEOUT_SEC = args.LOGGER_TIMEOUT_SEC
    RUN_SPECIFIED_BUILD = args.RUN_SPECIFIED_BUILD
    LOG_DIR_PATH = args.LOG_DIR_PATH
    
    execute_jlink_workflow(
        args.PATH_TEST_INFO, 
        args.PATH_JLINK_SCRIPT, 
        args.PATH_JLINK_LOG, 
        args.PATH_JLINK_LOG_ACC, 
        args.DEVICE_PART_NUMBER, 
        args.DEVICE_IP,
        args.LOG_DIR_PATH
    )
