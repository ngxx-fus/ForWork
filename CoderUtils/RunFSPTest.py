import os
import shutil
import yaml
import time
import argparse
import pylink

"""
Install dependencies:
> pip install PyYAML pylink-square
"""

# default parameters
PATH_TEST_INFO = r"build\r_icu\ra2e3_fpb\gcc\test_info.yml"
PATH_JLINK_LOG_ACC = "RTT_Viewer_All.log"
DEVICE_PART_NUMBER = "R7FA2E307"
DEVICE_IP = ""
LOGGER_TIMEOUT_SEC = 60
RUN_SPECIFIED_BUILD = ""
LOG_DIR_PATH = r"./.JLinkLogPath"

"""
/*
 * @brief Parses YAML config, flashes device and retrieves RTT logs using direct J-Link DLL via pylink.
 *        Parses log content at runtime to generate a summary list of test results.
 * @param info_path Path to the YAML configuration file.
 * @param log_acc_path Path to store the accumulated RTT logs.
 * @param part_number Target MCU part number.
 * @param ip Device IP address, can be empty.
 * @param log_dir_path Path to the directory where individual build logs will be saved.
 */
"""
def execute_jlink_workflow(info_path, log_acc_path, part_number, ip, log_dir_path):
    # Control flow: Check if log directory exists to clean up old logs
    if os.path.exists(log_dir_path):
        shutil.rmtree(log_dir_path)
        
    os.makedirs(log_dir_path)

    # Control flow: Check if accumulated log file exists
    if os.path.exists(log_acc_path):
        os.remove(log_acc_path)

    summary_list = []

    # Control flow: Handle file operations for YAML reading
    try:
        # Control flow: Open file for reading
        with open(info_path, 'r') as file:
            data = yaml.safe_load(file)
    # Control flow: Catch file exception
    except Exception:
        # Jump statement: Exit if file cannot be loaded
        return

    # Control flow: Check if YAML data is valid
    if not data:
        # Jump statement: Exit function if YAML is empty
        return

    # Control flow: Instantiate JLink controller (auto-detects DLL)
    jlink = pylink.JLink()

    # Control flow: Iterate through all top-level categories
    for category_name, category_data in data.items():
        # Control flow: Check if category data is a dictionary
        if not isinstance(category_data, dict):
            # Jump statement: Skip to next category on invalid structure
            continue
            
        # Control flow: Iterate through each project configuration
        for config_name, config_data in category_data.items():
            projects = config_data.get('projects', [])

            # Control flow: Check if projects list is empty
            if not projects:
                # Jump statement: Skip to next configuration if no projects
                continue

            app_path = projects[0].get('application', '')
            dependencies = projects[0].get('dependencies', [])
            rtt_addr_raw = str(projects[0].get('rtt_address', ''))
            
            # Control flow: Check if a specific build is requested and does not match the current app
            if RUN_SPECIFIED_BUILD and (RUN_SPECIFIED_BUILD != app_path):
                # Jump statement: Skip to next configuration as it does not match the specified build
                continue

            # Control flow: Check if RTT address is valid and convert to integer
            if rtt_addr_raw and rtt_addr_raw.startswith('0x'):
                rtt_addr = int(rtt_addr_raw, 16)
            # Control flow: Check if RTT address is valid without hex prefix
            elif rtt_addr_raw:
                rtt_addr = int(rtt_addr_raw, 16)
            else:
                rtt_addr = None

            exec_log_file = os.path.join(log_dir_path, f"{config_name}_exec.log")

            print(f"\n\n\n============================================================")
            print(f"--- Flashing device for [{category_name}] {config_name} ---")

            # Control flow: Try to execute hardware J-Link operations
            try:
                # Control flow: Connect using IP or USB
                if ip:
                    jlink.open(ip_addr=ip)
                else:
                    jlink.open()

                jlink.set_tif(pylink.enums.JLinkInterfaces.SWD)
                jlink.connect(part_number)
                jlink.reset(halt=True)

                # Control flow: Iterate through dependencies to flash
                for dep in dependencies:
                    print(f"Flashing dependency: {dep}")
                    jlink.flash_file(dep, 0)

                print(f"Flashing application: {app_path}")
                jlink.flash_file(app_path, 0)

                print(f"--- Starting execution for [{category_name}] {config_name} ---")
                print(f"============================================================\n")

                jlink.reset(halt=False)
                time.sleep(0.1)

                # Control flow: Start RTT based on provided address
                if rtt_addr is not None:
                    jlink.rtt_start(rtt_addr)
                else:
                    jlink.rtt_start()

                start_time = time.time()
                current_log = ""
                timeout_occurred = False

                # Control flow: Loop continuously to pull raw RTT data from memory
                while True:
                    # Control flow: Check if timeout limit is reached
                    if (time.time() - start_time) > LOGGER_TIMEOUT_SEC:
                        print(f"\n[TIMEOUT] Execution exceeded {LOGGER_TIMEOUT_SEC} seconds.\n")
                        timeout_occurred = True
                        # Jump statement: Break loop on timeout
                        break

                    # Fetch up to 1024 bytes from RTT channel 0
                    rtt_data = jlink.rtt_read(0, 1024)

                    # Control flow: Check if new RTT data is retrieved
                    if rtt_data:
                        text = "".join(map(chr, rtt_data))
                        print(text, end='', flush=True)
                        current_log += text

                        # Control flow: Check if tests have finished
                        if "FSP TESTS ALLDONE" in current_log:
                            time.sleep(0.5)
                            # Jump statement: Break loop after completion
                            break

                    time.sleep(0.01)

                jlink.rtt_stop()
                jlink.close()

            # Control flow: Catch J-Link hardware or DLL exceptions
            except Exception as e:
                print(f"JLink Operation Error: {e}")
                # Jump statement: Pass exception to move to next project configuration
                pass
            
            # Control flow: Open exec log file for writing execution data
            with open(exec_log_file, 'w') as exec_out:
                exec_out.write(current_log)

            # Control flow: Check if timeout occurred to append special note
            if timeout_occurred:
                summary_line = "TEST TIMED OUT"
            else:
                summary_line = "No test summary found"
                
            lines = current_log.split('\n')
            
            # Control flow: Iterate through log lines to find metrics
            for line in lines:
                # Control flow: Check if line contains test metrics pattern
                if "Tests" in line and "Failures" in line and "Ignored" in line:
                    summary_line = line.strip()
                    # Jump statement: Break loop once summary is found
                    break
                    
            summary_list.append(f"{summary_line} | BUILD: {app_path} | CATEGORY: {category_name}")
            
            # Control flow: Open accumulated log file to append
            with open(log_acc_path, 'a') as acc_log_file:
                acc_log_file.write(f"###################### Flash Info: SREC={app_path} | RTTAddress={rtt_addr_raw} | Category={category_name} ######################\n")
                acc_log_file.write(current_log)
                acc_log_file.write("\n\n")
            
    # Control flow: Check if summary list contains items
    if summary_list:
        print("\n###################### FINAL TEST SUMMARY LIST ######################")
        # Control flow: Iterate through summary items
        for item in summary_list:
            print(item)
        print("#####################################################################\n")

    # Jump statement: Return successfully
    return

# Control flow: Check if executed as main script
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run FSP Tests via direct pylink API.")
    
    parser.add_argument("-PATH_TEST_INFO", type=str, default=PATH_TEST_INFO, help="Path to test info YAML config")
    parser.add_argument("-PATH_JLINK_LOG_ACC", type=str, default=PATH_JLINK_LOG_ACC, help="Path to accumulated log")
    parser.add_argument("-DEVICE_PART_NUMBER", type=str, default=DEVICE_PART_NUMBER, help="Target MCU part number")
    parser.add_argument("-DEVICE_IP", type=str, default=DEVICE_IP, help="Device IP address")
    parser.add_argument("-LOGGER_TIMEOUT_SEC", type=int, default=LOGGER_TIMEOUT_SEC, help="Logger timeout in seconds")
    parser.add_argument("-RUN_SPECIFIED_BUILD", type=str, default=RUN_SPECIFIED_BUILD, help="Specify exact app_path to flash and test")
    parser.add_argument("-LOG_DIR_PATH", type=str, default=LOG_DIR_PATH, help="Directory to store individual build logs")
    
    args = parser.parse_args()

    # Override variables in global scope directly
    LOGGER_TIMEOUT_SEC = args.LOGGER_TIMEOUT_SEC
    RUN_SPECIFIED_BUILD = args.RUN_SPECIFIED_BUILD
    LOG_DIR_PATH = args.LOG_DIR_PATH
    
    execute_jlink_workflow(
        args.PATH_TEST_INFO, 
        args.PATH_JLINK_LOG_ACC, 
        args.DEVICE_PART_NUMBER, 
        args.DEVICE_IP,
        args.LOG_DIR_PATH
    )
