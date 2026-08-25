import os
import shutil
import yaml
import subprocess
import time
import argparse
import sys

"""
================================================================================
USAGE NOTE:
This script automates the process of flashing firmware and capturing RTT logs 
via SEGGER J-Link tools. It parses a YAML configuration file to get project 
details, executes J-Link to flash the application (and its dependencies), 
and uses JLinkRTTLogger to capture test execution outputs.

Dependencies:
    > pip install PyYAML

Basic execution:
    > python script_name.py

Override specific parameters:
    > python script_name.py -DEVICE_PART_NUMBER R7FA8D1BH -LOGGER_TIMEOUT_SEC 60 -RUN_SPECIFIED_BUILD "path/to/app.srec"
================================================================================
"""

# Default parameters
JLINK_PATH              = r"/home/coder/workspace/JLink_V950/JLinkExe"
RTT_LOGGER_PATH         = r"/home/coder/workspace/JLink_V950/JLinkRTTLoggerExe"
PATH_TEST_INFO          = r"build/r_gpt/ra8d1_ek/gcc/test_info.yml"
PATH_JLINK_SCRIPT       = "CuzJFlash.jlink"
PATH_JLINK_LOG          = "RTT_Viewer.log"
PATH_JLINK_LOG_ACC      = "RTT_Viewer_All.log"

# NOTES:
#       ra8m2_ek:       R7KA8M2JF_CPU0
#       ra2ek_fpb:      R7FA2E307
#       ra2l1_ek:       R7FA2L1AB
#       ra8d1_ek:       R7FA8D1BH
DEVICE_PART_NUMBER      = "R7FA8D1BH"
DEVICE_IP               = "127.0.0.1:19020"
LOGGER_TIMEOUT_SEC      = 30
RUN_SPECIFIED_BUILD     = ""
LOG_DIR_PATH            = r"./.JLinkLogPath"

# Flash detection phases (Keyword, Status, Percentage)
FLASH_DETECTION_LIST = [
    ("J-Link Command File read successfully.",  "Init",                 5),
    ("Firmware: J-Link OB-",                    "Connecting",           10),
    ("InitTarget() end - Took",                 "Connected",            15),
    ("Downloading file",                        "Flashing",             40),
    ("J-Link>r",                                "Reset",                80),
    ("J-Link>g",                                "Start",                90),
    ("Script processing completed",             "Done",                 100),
]

EXEC_ACTION_LIST = [
    ("Terminated",                              "Stop exec"),
    ("ShowError",                               "Show all error entire the error line")
]

EXEC_DETECTION_LIST = [
    ("Shutting down... Done.",                  "Shutdown",             "Action=Terminated"),
    ("ERROR: Can not connect to J-Link",        "Error",                "Action=ShowError,Terminated")
]

def execute_jlink_workflow(info_path, script_path, log_path, log_acc_path, part_number, ip, log_dir_path):
    # Clean up old logs
    if os.path.exists(log_dir_path):
        shutil.rmtree(log_dir_path)
        
    os.makedirs(log_dir_path, exist_ok=True)

    if os.path.exists(log_path):
        os.remove(log_path)
        
    if os.path.exists(log_acc_path):
        os.remove(log_acc_path)

    summary_list = []

    # Parse YAML configuration
    with open(info_path, 'r') as file:
        data = yaml.safe_load(file)

    if not data:
        return

    # Iterate through configuration
    for category_name, category_data in data.items():
        if not isinstance(category_data, dict):
            continue
            
        for config_name, config_data in category_data.items():
            projects = config_data.get('projects', [])
            if not projects:
                continue

            app_path = projects[0].get('application', '')
            dependencies = projects[0].get('dependencies', [])
            rtt_addr_raw = str(projects[0].get('rtt_address', ''))
            
            if RUN_SPECIFIED_BUILD and (RUN_SPECIFIED_BUILD != app_path):
                continue

            if rtt_addr_raw and not rtt_addr_raw.startswith('0x'):
                rtt_addr = f"0x{rtt_addr_raw}"
            else:
                rtt_addr = rtt_addr_raw

            flash_log_file = os.path.join(log_dir_path, f"{config_name}_flash.log")
            exec_log_file = os.path.join(log_dir_path, f"{config_name}_exec.log")
            logger_stdout_file = os.path.join(log_dir_path, f"{config_name}_rtt_tool.log")

            # Generate J-Link Script
            with open(script_path, 'w') as script_file:
                script_file.write("speed 4000\n")
                if dependencies:
                    for dep in dependencies:
                        script_file.write(f"loadfile {dep}\n")
                        
                script_file.write(f"loadfile {app_path}\n")
                script_file.write("r\n")
                script_file.write("g\n")
                script_file.write("q\n")

            flash_cmd = [JLINK_PATH]
            if ip:
                flash_cmd.extend(["-ip", ip])

            flash_cmd.extend([
                "-device", part_number,
                "-if", "SWD",
                "-speed", "4000",
                "-autoconnect", "1",
                "-CommanderScript", script_path
            ])
            
            print(f"\n\n============================================================")
            print(f"--- Flashing device for [{category_name}] {config_name} ---")
            
            # Execute flash command
            with open(flash_log_file, 'w') as flash_out:
                flash_process = subprocess.Popen(flash_cmd, stdout=flash_out, stderr=subprocess.STDOUT)
                
                flash_start_time = time.time()
                last_read_pos = 0
                current_status = "Connecting & Initializing..."
                estimated_pct = 0
                
                while flash_process.poll() is None:
                    elapsed = int(time.time() - flash_start_time)
                    
                    # Parse flash log live to update status
                    if os.path.exists(flash_log_file):
                        try:
                            with open(flash_log_file, 'r', errors='ignore') as f:
                                f.seek(last_read_pos)
                                content = f.read()
                                if content:
                                    last_read_pos = f.tell()
                                    # Match phases from detection list
                                    for keyword, phase, pct in FLASH_DETECTION_LIST:
                                        if keyword in content:
                                            current_status = phase
                                            estimated_pct = pct
                        except Exception:
                            pass
                    
                    # Print status padded to exactly 100 characters to overwrite previous line
                    status_msg = f"    -> [{estimated_pct:3d}%] {current_status} ({elapsed}s)"
                    sys.stdout.write(f"\r{status_msg:<100}")
                    sys.stdout.flush()
                    time.sleep(0.3)
                
                # Finalize progress
                total_flash_time = int(time.time() - flash_start_time)
                done_msg = f"    -> [100%] Flashing completed successfully in {total_flash_time}s."
                sys.stdout.write(f"\r{done_msg:<100}\n")
                sys.stdout.flush()

            # Prepare for logging
            if os.path.exists(log_path):
                os.remove(log_path)

            log_cmd = [RTT_LOGGER_PATH]
            if ip:
                log_cmd.extend(["-ip", ip])

            log_cmd.extend([
                "-device", part_number,
                "-if", "SWD",
                "-speed", "4000"
            ])
            
            if rtt_addr:
                log_cmd.extend(["-RTTAddress", rtt_addr])
                
            log_cmd.extend([
                "-RTTChannel", "0",
                log_path
            ])

            print(f"--- Starting execution for [{category_name}] {config_name} ---")
            print(f"============================================================\n")
            
            # Start RTT Logger
            tool_out = open(logger_stdout_file, 'w')
            logger_process = subprocess.Popen(log_cmd, stdout=tool_out, stderr=subprocess.STDOUT)
            
            start_time = time.time()
            last_pos = 0
            tool_last_pos = 0
            current_log = ""
            current_tool_log = ""
            timeout_occurred = False
            terminate_early = False
            exec_status = ""
            triggered_errors = set()
            process_exited = False

            while True:
                # Check if tool process died unexpectedly
                if logger_process.poll() is not None:
                    process_exited = True

                # Check timeout
                if (time.time() - start_time) > LOGGER_TIMEOUT_SEC:
                    print(f"\n[TIMEOUT] Execution exceeded {LOGGER_TIMEOUT_SEC} seconds. Terminating...\n")
                    logger_process.terminate()
                    timeout_occurred = True
                    break
                
                # 1. Safely read target RTT output
                if os.path.exists(log_path):
                    try:
                        file_size = os.path.getsize(log_path)
                        if file_size > last_pos:
                            with open(log_path, 'rb') as log_file:
                                log_file.seek(last_pos)
                                new_bytes = log_file.read()
                                last_pos = log_file.tell()
                                
                            new_data = new_bytes.decode('utf-8', errors='replace')
                            if new_data:
                                print(new_data, end='', flush=True)
                                current_log += new_data
                    except Exception:
                        pass

                # 2. Safely read Tool's own stdout/stderr
                if os.path.exists(logger_stdout_file):
                    try:
                        with open(logger_stdout_file, 'r', errors='replace') as tool_file:
                            tool_file.seek(tool_last_pos)
                            new_tool_data = tool_file.read()
                            if new_tool_data:
                                tool_last_pos = tool_file.tell()
                                current_tool_log += new_tool_data
                    except Exception:
                        pass
                
                # Combine both logs to detect errors at any level (Tool level or Target level)
                combined_log = current_log + "\n" + current_tool_log

                # Check execution errors and early termination
                for keyword, status, action_str in EXEC_DETECTION_LIST:
                    if keyword in combined_log and keyword not in triggered_errors:
                        triggered_errors.add(keyword)
                        actions = action_str.replace("Action=", "").split(",")
                        
                        if "ShowError" in actions:
                            error_line = next((line for line in combined_log.splitlines() if keyword in line), "Unknown Error")
                            print(f"\n[ERROR DETECTED] {error_line}")
                        
                        if "Terminated" in actions:
                            print(f"\n[TERMINATED EARLY] Status: {status}")
                            exec_status = f"FAILED ({status})"
                            time.sleep(0.5)
                            logger_process.terminate()
                            terminate_early = True
                            break
                            
                if terminate_early:
                    break

                # Check normal completion
                if "FSP TESTS ALLDONE" in current_log:
                    time.sleep(0.5)
                    logger_process.terminate()
                    break

                # If process died and we finished our final read iteration, break out
                if process_exited:
                    if not terminate_early and "FSP TESTS ALLDONE" not in current_log:
                        exec_status = "FAILED (Tool Exited Unexpectedly)"
                    break
                
                time.sleep(0.2)

            logger_process.wait()
            tool_out.close()

            # Save combined logs
            with open(exec_log_file, 'w') as exec_out:
                exec_out.write("=== TOOL STDOUT/STDERR ===\n")
                exec_out.write(current_tool_log)
                exec_out.write("\n=== TARGET RTT LOG ===\n")
                exec_out.write(current_log)

            # Parse results
            summary_line = "No test summary found"
            if timeout_occurred:
                summary_line = "TEST TIMED OUT"
            elif exec_status:
                summary_line = exec_status
            else:
                for line in current_log.splitlines():
                    if "Tests" in line and "Failures" in line and "Ignored" in line:
                        summary_line = line.strip()
                        break
                    
            summary_list.append(f"{summary_line} | BUILD: {app_path} | CATEGORY: {category_name}")
            
            # Append global log
            with open(log_acc_path, 'a') as acc_log_file:
                acc_log_file.write(f"###################### Flash Info: SREC={app_path} | RTTAddress={rtt_addr_raw} | Category={category_name} ######################\n")
                acc_log_file.write(current_tool_log)
                acc_log_file.write(current_log)
                acc_log_file.write("\n\n")
            
            # Clean up temporary logs
            try:
                os.remove(log_path)
            except OSError:
                pass

    # Print summary
    if summary_list:
        print("\n###################### FINAL TEST SUMMARY LIST ######################")
        for item in summary_list:
            print(item)
        print("#####################################################################\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run FSP Tests with override parameters.")
    parser.add_argument("-JLINK_PATH", type=str, default=JLINK_PATH)
    parser.add_argument("-RTT_LOGGER_PATH", type=str, default=RTT_LOGGER_PATH)
    parser.add_argument("-PATH_TEST_INFO", type=str, default=PATH_TEST_INFO)
    parser.add_argument("-PATH_JLINK_SCRIPT", type=str, default=PATH_JLINK_SCRIPT)
    parser.add_argument("-PATH_JLINK_LOG", type=str, default=PATH_JLINK_LOG)
    parser.add_argument("-PATH_JLINK_LOG_ACC", type=str, default=PATH_JLINK_LOG_ACC)
    parser.add_argument("-DEVICE_PART_NUMBER", type=str, default=DEVICE_PART_NUMBER)
    parser.add_argument("-DEVICE_IP", type=str, default=DEVICE_IP)
    parser.add_argument("-LOGGER_TIMEOUT_SEC", type=int, default=LOGGER_TIMEOUT_SEC)
    parser.add_argument("-RUN_SPECIFIED_BUILD", type=str, default=RUN_SPECIFIED_BUILD)
    parser.add_argument("-LOG_DIR_PATH", type=str, default=LOG_DIR_PATH)
    
    args = parser.parse_args()

    print(f"args.JLINK_PATH          ={args.JLINK_PATH}")
    print(f"args.RTT_LOGGER_PATH     ={args.RTT_LOGGER_PATH}")
    print(f"args.PATH_JLINK_SCRIPT   ={args.PATH_JLINK_SCRIPT}")
    print(f"args.PATH_JLINK_LOG      ={args.PATH_JLINK_LOG}")
    print(f"args.PATH_TEST_INFO      ={args.PATH_TEST_INFO}")
    print(f"args.PATH_JLINK_LOG_ACC  ={args.PATH_JLINK_LOG_ACC}")
    print(f"args.DEVICE_PART_NUMBER  ={args.DEVICE_PART_NUMBER}")
    print(f"args.DEVICE_IP           ={args.DEVICE_IP}")
    print(f"args.LOGGER_TIMEOUT_SEC  ={args.LOGGER_TIMEOUT_SEC}")
    print(f"args.RUN_SPECIFIED_BUILD ={args.RUN_SPECIFIED_BUILD}")
    print(f"args.LOG_DIR_PATH        ={args.LOG_DIR_PATH}")

    (
        execute_jlink_workflow(
            args.PATH_TEST_INFO, 
            args.PATH_JLINK_SCRIPT, 
            args.PATH_JLINK_LOG, 
            args.PATH_JLINK_LOG_ACC, 
            args.DEVICE_PART_NUMBER, 
            args.DEVICE_IP,
            args.LOG_DIR_PATH
        )
    )
