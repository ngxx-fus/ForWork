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
PATH_TEST_INFO = r"build/TestInfo.yml"
PATH_JLINK_LOG_ACC = "RTT_Viewer_All.log"
# NOTES:
#       ra8m2_ek:       R7KA8M2JF_CPU0
#       ra2ek_fpb:      R7FA2E307
#       ra2l1_ek:       R7FA2L1AB
DEVICE_PART_NUMBER  = "R7FA2L1AB"
DEVICE_IP           = "127.0.0.1:19020"
LOGGER_TIMEOUT_SEC  = 60
RUN_SPECIFIED_BUILD = ""
LOG_DIR_PATH        = r"./.JLinkLogPath"

def create_flash_plan(category_name, project):
    """
    Create and validate an ordered list of firmware images to flash.

    For a TrustZone (TZ) build, the project is identified when either the
    category name or the project name is "tz", case-insensitively. The Secure
    Code (SC) image must be listed under ``dependencies`` and is always flashed
    before the Non-Secure/Non-Secure Callable (NS/NSC) application image.

    Flash order:
        TZ build:
            1. Secure Code (SC) image(s) from ``dependencies``
            2. NS/NSC application image from ``application``

        Non-TZ build:
            1. Dependency image(s) from ``dependencies``
            2. Main application image from ``application``

    All image paths are validated before any target programming begins. This
    prevents a partially programmed target when an image path is missing or
    invalid.

    Args:
        category_name (str):
            Top-level category name from the YAML configuration, such as
            ``default`` or ``tz``.

        project (dict):
            Project information read from the YAML configuration. Expected
            fields are:

            - ``application`` (str): Path to the main application image.
            - ``dependencies`` (list[str]): Paths to dependency images.
            - ``name`` (str, optional): Project type/name, such as ``tz``.

    Returns:
        tuple:
            A tuple containing:

            - ``is_tz_build`` (bool): True when the project is a TZ build.
            - ``flash_plan`` (list[tuple[str, str]]): Ordered pairs of
              ``(image_type, image_path)`` to be flashed sequentially.

    Raises:
        ValueError:
            If the application path is empty, ``dependencies`` is not a list,
            a TZ build has no secure dependency, or an image path is empty.

        FileNotFoundError:
            If any application or dependency image does not exist.

    Notes:
        The caller must execute ``flash_plan`` in the returned order and must
        not reset, erase, or disconnect the target between the SC and NS/NSC
        programming operations.
    """
    application = project.get("application", "")
    dependencies = project.get("dependencies", []) or []
    project_name = str(project.get("name", ""))

    is_tz_build = (
        str(category_name).strip().lower() == "tz"
        or project_name.strip().lower() == "tz"
    )

    if not application:
        raise ValueError("No application image is configured")

    if not isinstance(dependencies, list):
        raise ValueError("'dependencies' must be a list")

    flash_plan = []

    if is_tz_build:
        if not dependencies:
            raise ValueError(
                "TZ build has no secure image in 'dependencies'. "
                "The secure image must be flashed before the non-secure image."
            )

        for secure_image in dependencies:
            flash_plan.append(("SC", secure_image))

        flash_plan.append(("NS/NSC", application))
    else:
        for dependency in dependencies:
            flash_plan.append(("Dependency", dependency))

        flash_plan.append(("Application", application))

    # Validate all files before changing the target.
    for image_type, image_path in flash_plan:
        if not image_path:
            raise ValueError(f"{image_type} image path is empty")

        if not os.path.isfile(image_path):
            raise FileNotFoundError(
                f"{image_type} image does not exist: {image_path}"
            )

    return is_tz_build, flash_plan

def execute_jlink_workflow(
    info_path,
    log_acc_path,
    part_number,
    ip,
    log_dir_path
):
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
    # Clean old log directory.
    if os.path.exists(log_dir_path):
        shutil.rmtree(log_dir_path)

    os.makedirs(log_dir_path, exist_ok=True)

    # Clean accumulated log.
    if os.path.exists(log_acc_path):
        os.remove(log_acc_path)

    summary_list = []

    # Load YAML file.
    try:
        with open(info_path, "r", encoding="utf-8") as file:
            data = yaml.safe_load(file)
    except Exception as e:
        print(f"Failed to load YAML file '{info_path}': {e}")
        return

    if not data:
        print(f"YAML file is empty: {info_path}")
        return

    # Iterate through all categories.
    for category_name, category_data in data.items():
        if not isinstance(category_data, dict):
            print(f"Skipping invalid category: {category_name}")
            continue

        # Iterate through configurations.
        for config_name, config_data in category_data.items():
            if not isinstance(config_data, dict):
                print(
                    f"Skipping invalid configuration: "
                    f"[{category_name}] {config_name}"
                )
                continue

            projects = config_data.get("projects", [])

            if not projects:
                continue

            project = projects[0]

            if not isinstance(project, dict):
                print(
                    f"Invalid project data for "
                    f"[{category_name}] {config_name}"
                )
                continue

            app_path = project.get("application", "")
            rtt_addr_raw = str(project.get("rtt_address", "")).strip()

            # Run only the requested build if specified.
            if RUN_SPECIFIED_BUILD and RUN_SPECIFIED_BUILD != app_path:
                continue

            # Parse RTT address as hexadecimal.
            try:
                if rtt_addr_raw:
                    rtt_addr = int(rtt_addr_raw, 16)
                else:
                    rtt_addr = None
            except ValueError:
                print(
                    f"Invalid RTT address '{rtt_addr_raw}' for "
                    f"[{category_name}] {config_name}"
                )
                continue

            # Include category in filename to prevent duplicate names.
            exec_log_file = os.path.join(
                log_dir_path,
                f"{category_name}_{config_name}_exec.log"
            )

            print("\n\n============================================================")
            print(
                f"--- Flashing device for "
                f"[{category_name}] {config_name} ---"
            )

            current_log = ""
            timeout_occurred = False
            operation_error = None
            jlink_opened = False
            rtt_started = False

            # Create a separate J-Link object for each build.
            jlink = pylink.JLink()

            try:
                # Create and validate flash order before connecting.
                is_tz_build, flash_plan = create_flash_plan(
                    category_name,
                    project
                )

                if is_tz_build:
                    print("TZ flash sequence:")
                    print("  1. SC image(s) from dependencies")
                    print("  2. NS/NSC image from application")
                else:
                    print("Standard flash sequence:")
                    print("  1. Dependencies")
                    print("  2. Application")

                # Connect to J-Link.
                if ip:
                    jlink.open(ip_addr=ip)
                else:
                    jlink.open()

                jlink_opened = True

                jlink.set_tif(pylink.enums.JLinkInterfaces.SWD)
                jlink.connect(part_number)
                jlink.reset(halt=True)

                # Flash all images in the required order.
                #
                # For TZ:
                #   dependencies (SC) -> application (NS/NSC)
                #
                # There is no reset or disconnect between images.
                for index, (image_type, image_path) in enumerate(
                    flash_plan,
                    start=1
                ):
                    print(
                        f"[{index}/{len(flash_plan)}] "
                        f"Flashing {image_type}: {image_path}"
                    )

                    # flash_file() completes before the next statement,
                    # so the image order is guaranteed.
                    jlink.flash_file(image_path, 0)

                    print(
                        f"[{index}/{len(flash_plan)}] "
                        f"{image_type} completed"
                    )

                print(
                    f"--- Starting execution for "
                    f"[{category_name}] {config_name} ---"
                )
                print(
                    "============================================================\n"
                )

                # Reset only after both SC and NS/NSC are programmed.
                jlink.reset(halt=False)
                time.sleep(0.1)

                # Start RTT.
                if rtt_addr is not None:
                    jlink.rtt_start(rtt_addr)
                else:
                    jlink.rtt_start()

                rtt_started = True
                start_time = time.time()

                # Read RTT output.
                while True:
                    elapsed_time = time.time() - start_time

                    if elapsed_time > LOGGER_TIMEOUT_SEC:
                        print(
                            f"\n[TIMEOUT] Execution exceeded "
                            f"{LOGGER_TIMEOUT_SEC} seconds.\n"
                        )
                        timeout_occurred = True
                        break

                    rtt_data = jlink.rtt_read(0, 1024)

                    if rtt_data:
                        text = bytes(rtt_data).decode(
                            "utf-8",
                            errors="replace"
                        )

                        print(text, end="", flush=True)
                        current_log += text

                        if "FSP TESTS ALLDONE" in current_log:
                            time.sleep(0.5)
                            break

                    time.sleep(0.01)

            except Exception as e:
                operation_error = str(e)
                print(
                    f"J-Link operation failed for "
                    f"[{category_name}] {config_name}: {e}"
                )

            finally:
                # Always stop RTT if it was started.
                if rtt_started:
                    try:
                        jlink.rtt_stop()
                    except Exception as e:
                        print(f"Warning: failed to stop RTT: {e}")

                # Always close J-Link if it was opened.
                if jlink_opened:
                    try:
                        jlink.close()
                    except Exception as e:
                        print(f"Warning: failed to close J-Link: {e}")

            # Write individual execution log.
            try:
                with open(
                    exec_log_file,
                    "w",
                    encoding="utf-8"
                ) as exec_out:
                    exec_out.write(current_log)
            except Exception as e:
                print(f"Failed to write log '{exec_log_file}': {e}")

            # Generate summary.
            if operation_error:
                summary_line = f"J-LINK ERROR: {operation_error}"
            elif timeout_occurred:
                summary_line = "TEST TIMED OUT"
            else:
                summary_line = "No test summary found"

                for line in current_log.splitlines():
                    if (
                        "Tests" in line
                        and "Failures" in line
                        and "Ignored" in line
                    ):
                        summary_line = line.strip()
                        break

            summary_list.append(
                f"{summary_line} "
                f"| BUILD: {app_path} "
                f"| CATEGORY: {category_name}"
            )

            # Append to accumulated log.
            try:
                with open(
                    log_acc_path,
                    "a",
                    encoding="utf-8"
                ) as acc_log_file:
                    acc_log_file.write(
                        "###################### "
                        f"Flash Info: SREC={app_path} "
                        f"| RTTAddress={rtt_addr_raw} "
                        f"| Category={category_name} "
                        "######################\n"
                    )
                    acc_log_file.write(current_log)
                    acc_log_file.write("\n\n")
            except Exception as e:
                print(
                    f"Failed to append accumulated log "
                    f"'{log_acc_path}': {e}"
                )

    # Print final summary.
    if summary_list:
        print(
            "\n###################### "
            "FINAL TEST SUMMARY LIST "
            "######################"
        )

        for item in summary_list:
            print(item)

        print(
            "########################################################"
            "#############\n"
        )

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
