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
JLINK_PATH              = r"/home/coder/workspace/JLink_V950/JLinkExe"
RTT_LOGGER_PATH         = r"/home/coder/workspace/JLink_V950/JLinkRTTLoggerExe"
PATH_TEST_INFO          = r"build/TestInfo.yml"
PATH_JLINK_SCRIPT       = "CuzJFlash.jlink"
PATH_JLINK_LOG          = "RTT_Viewer.log"
PATH_JLINK_LOG_ACC      = "RTT_Viewer_All.log"
# NOTES:
#       ra8m2_ek:       R7KA8M2JF_CPU0
#       ra2ek_fpb:      R7FA2E307
#       ra2l1_ek:       R7FA2L1AB
DEVICE_PART_NUMBER      = "R7FA2L1AB"
DEVICE_IP               = "127.0.0.1:19020"
LOGGER_TIMEOUT_SEC      = 15
RUN_SPECIFIED_BUILD     = ""
LOG_DIR_PATH            = r"./.JLinkLogPath"


def execute_jlink_workflow(info_path, script_path, log_path, log_acc_path, part_number, ip, log_dir_path):
    # Check if log directory exists to clean up old logs
    if os.path.exists(log_dir_path):
        shutil.rmtree(log_dir_path)
        
    os.makedirs(log_dir_path, exist_ok=True)

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

    if not data:
        return

    # Iterate through all top-level categories
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

            # Tạo J-Link Script
            with open(script_path, 'w') as script_file:
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
            
            with open(flash_log_file, 'w') as flash_out:
                subprocess.run(flash_cmd, stdout=flash_out, stderr=subprocess.STDOUT)

            # Đảm bảo xóa log cũ trước khi RTT Logger khởi chạy
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
            
            # Chặn stdout/stderr của tool JLinkRTTLogger in ra màn hình hoặc đè vào file RTT bằng cách lưu sang file riêng
            tool_out = open(logger_stdout_file, 'w')
            logger_process = subprocess.Popen(log_cmd, stdout=tool_out, stderr=subprocess.STDOUT)
            
            start_time = time.time()
            last_pos = 0
            current_log = ""
            timeout_occurred = False

            while True:
                # Kiểm tra Timeout
                if (time.time() - start_time) > LOGGER_TIMEOUT_SEC:
                    print(f"\n[TIMEOUT] Execution exceeded {LOGGER_TIMEOUT_SEC} seconds. Terminating RTT Logger...\n")
                    logger_process.terminate()
                    timeout_occurred = True
                    break
                
                # Đọc log RTT an toàn
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
                                    
                            # Kiểm tra test kết thúc
                            if "FSP TESTS ALLDONE" in current_log:
                                time.sleep(0.5)
                                logger_process.terminate()
                                break
                    except Exception:
                        pass
                
                time.sleep(0.2)

            logger_process.wait()
            tool_out.close()

            # Đọc vét lần cuối
            if os.path.exists(log_path):
                try:
                    with open(log_path, 'rb') as log_file:
                        log_file.seek(last_pos)
                        new_bytes = log_file.read()
                        new_data = new_bytes.decode('utf-8', errors='replace')
                        if new_data:
                            print(new_data, end='', flush=True)
                            current_log += new_data
                except Exception:
                    pass
                
                # Lưu file exec riêng của config
                with open(exec_log_file, 'w') as exec_out:
                    exec_out.write(current_log)

                # Parse kết quả test
                summary_line = "TEST TIMED OUT" if timeout_occurred else "No test summary found"
                for line in current_log.splitlines():
                    if "Tests" in line and "Failures" in line and "Ignored" in line:
                        summary_line = line.strip()
                        break
                        
                summary_list.append(f"{summary_line} | BUILD: {app_path} | CATEGORY: {category_name}")
                
                # Ghi vào file tổng
                with open(log_acc_path, 'a') as acc_log_file:
                    acc_log_file.write(f"###################### Flash Info: SREC={app_path} | RTTAddress={rtt_addr_raw} | Category={category_name} ######################\n")
                    acc_log_file.write(current_log)
                    acc_log_file.write("\n\n")
                
                # Dọn file log tạm
                try:
                    os.remove(log_path)
                except OSError:
                    pass

    # In bảng tổng kết
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

    execute_jlink_workflow(
        args.PATH_TEST_INFO, 
        args.PATH_JLINK_SCRIPT, 
        args.PATH_JLINK_LOG, 
        args.PATH_JLINK_LOG_ACC, 
        args.DEVICE_PART_NUMBER, 
        args.DEVICE_IP,
        args.LOG_DIR_PATH
    )
