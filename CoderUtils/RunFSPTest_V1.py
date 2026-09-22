#!/usr/bin/env python3

import argparse
import os
import shutil
import subprocess
import sys
import time

import yaml


"""
================================================================================
USAGE NOTE

This script automates firmware programming and RTT log collection using
SEGGER J-Link command-line tools.

For a TrustZone build, the required programming order is:

    1. Secure Code (SC) image(s) from "dependencies"
    2. Non-Secure/NSC application image from "application"
    3. Reset the target
    4. Start target execution
    5. Start RTT Logger

No reset, disconnect, or explicit erase is performed between programming the
SC image and the NS/NSC image.

Dependencies:

    pip install PyYAML

Basic execution:

    python RunFSPTest.py

Override selected parameters:

    python RunFSPTest.py \
        -DEVICE_PART_NUMBER R7FA8D1BH \
        -LOGGER_TIMEOUT_SEC 60 \
        -RUN_SPECIFIED_BUILD "path/to/application.srec"

Remote J-Link connection:

    python RunFSPTest.py \
        -DEVICE_IP "127.0.0.1:19020"

USB J-Link connection:

    python RunFSPTest.py \
        -DEVICE_IP ""

================================================================================
"""


# =============================================================================
# Default parameters
# =============================================================================

JLINK_PATH              = r"C:\Program Files\SEGGER\JLink_V796e\JLink.exe"
RTT_LOGGER_PATH         = r"C:\Program Files\SEGGER\JLink_V796e\JLinkRTTLogger.exe"
PATH_TEST_INFO          = r"build/r_gpt/ra8d1_ek/ac6/test_info.yml"
PATH_JLINK_SCRIPT       = "CuzJFlash.jlink"
PATH_JLINK_LOG          = "RTT_Viewer.log"
PATH_JLINK_LOG_ACC      = "RTT_Viewer_All.log"

# Target device examples:
#
#   ra8m2_ek:  R7KA8M2JF_CPU0
#   ra2ek_fpb: R7FA2E307
#   ra2l1_ek:  R7FA2L1AB
#   ra8d1_ek:  R7FA8D1BH
#
DEVICE_PART_NUMBER = "R7FA8D1BH"

# Empty DEVICE_IP means use a local J-Link through USB.
#
# Example remote connection:
#   127.0.0.1:19020
DEVICE_IP = ""

LOGGER_TIMEOUT_SEC = 30

# Empty string means run all applications from the YAML file.
RUN_SPECIFIED_BUILD = ""

LOG_DIR_PATH = r"./.JLinkLogPath"


# =============================================================================
# J-Link progress detection
# =============================================================================

# Each entry contains:
#
#   (J-Link output keyword, displayed phase, estimated percentage)
#
# The percentage is only an estimated progress indicator. It does not indicate
# the exact number of programmed bytes.
FLASH_DETECTION_LIST = [
    (
        "J-Link Command File read successfully.",
        "Init",
        5,
    ),
    (
        "Firmware: J-Link OB-",
        "Connecting",
        10,
    ),
    (
        "InitTarget() end - Took",
        "Connected",
        15,
    ),
    (
        "Downloading file",
        "Flashing",
        40,
    ),
    (
        "J-Link>r",
        "Reset",
        80,
    ),
    (
        "J-Link>g",
        "Start",
        90,
    ),
    (
        "Script processing completed",
        "Done",
        100,
    ),
]


# J-Link output strings that indicate programming failure.
FLASH_ERROR_KEYWORDS = [
    "Cannot connect to J-Link",
    "Can not connect to J-Link",
    "Cannot connect to target",
    "Can not connect to target",
    "Failed to connect",
    "Could not connect",
    "Error while programming flash",
    "Programming failed",
    "Failed to download file",
    "Could not download file",
    "File could not be opened",
    "Cannot open file",
    "Error: Could not open",
    "Script processing failed",
    "Unknown command",
]


# RTT Logger errors that require early termination.
#
# "Shutting down... Done." is intentionally not included because it can be a
# normal RTT Logger shutdown message.
EXEC_DETECTION_LIST = [
    (
        "ERROR: Can not connect to J-Link",
        "Cannot connect to J-Link",
    ),
    (
        "ERROR: Cannot connect to J-Link",
        "Cannot connect to J-Link",
    ),
    (
        "ERROR: Could not connect to target",
        "Cannot connect to target",
    ),
    (
        "ERROR: Cannot connect to target",
        "Cannot connect to target",
    ),
]


def sanitize_filename(value):
    """
    Convert text to a filename-safe value.

    Args:
        value:
            Text to sanitize.

    Returns:
        str:
            Text with Windows-invalid filename characters replaced.
    """
    result = str(value)

    for character in '<>:"/\\|?*':
        result = result.replace(character, "_")

    return result


def quote_jlink_path(path):
    """
    Quote a file path for use in a J-Link Commander script.

    Embedded double quotes are escaped to prevent malformed commands.

    Args:
        path (str):
            Firmware image path.

    Returns:
        str:
            Quoted path suitable for a "loadfile" command.
    """
    path = str(path).replace('"', '\\"')
    return f'"{path}"'


def create_flash_plan(category_name, project):
    """
    Create and validate an ordered list of firmware images to flash.

    A project is identified as a TrustZone build when either:

        - The top-level YAML category is "tz", or
        - The project "name" field is "tz".

    Comparisons are case-insensitive and ignore surrounding spaces.

    TrustZone flash order:

        1. Secure Code image(s) from "dependencies"
        2. Non-Secure/NSC application from "application"

    Standard flash order:

        1. Dependency image(s) from "dependencies"
        2. Main application from "application"

    All firmware files are validated before J-Link is started. This prevents
    partially programming the target when a required image does not exist.

    Args:
        category_name (str):
            Top-level YAML category, for example "default" or "tz".

        project (dict):
            Project configuration containing:

                application:
                    Path to the main application image.

                dependencies:
                    Ordered list of dependency images.

                name:
                    Optional project type, such as "tz".

    Returns:
        tuple:
            A pair containing:

                is_tz_build:
                    True if the project is a TrustZone project.

                flash_plan:
                    Ordered list of (image_type, image_path) tuples.

    Raises:
        ValueError:
            If the project format is invalid, the application is missing,
            dependencies is not a list, or a TrustZone build has no Secure
            image.

        FileNotFoundError:
            If a configured firmware image does not exist.

    Important:
        The caller must flash the returned images sequentially.

        For TrustZone, the caller must not reset, disconnect, or explicitly
        erase the target between programming SC and NS/NSC.
    """
    if not isinstance(project, dict):
        raise ValueError("Project configuration must be a dictionary")

    application = str(project.get("application", "")).strip()
    dependencies = project.get("dependencies", []) or []
    project_name = str(project.get("name", "")).strip()

    is_tz_build = (
        str(category_name).strip().lower() == "tz"
        or project_name.lower() == "tz"
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
                "The Secure Code image must be flashed before the "
                "Non-Secure/NSC image."
            )

        # Add all Secure Code images first.
        for secure_image in dependencies:
            flash_plan.append(("SC", str(secure_image).strip()))

        # Add the Non-Secure/NSC application after all Secure images.
        flash_plan.append(("NS/NSC", application))

    else:
        # Preserve the YAML dependency order for standard builds.
        for dependency in dependencies:
            flash_plan.append(
                ("Dependency", str(dependency).strip())
            )

        flash_plan.append(("Application", application))

    # Validate all images before starting J-Link.
    for image_type, image_path in flash_plan:
        if not image_path:
            raise ValueError(f"{image_type} image path is empty")

        if not os.path.isfile(image_path):
            raise FileNotFoundError(
                f"{image_type} image does not exist: {image_path}"
            )

    return is_tz_build, flash_plan


def normalize_rtt_address(raw_address):
    """
    Normalize the RTT address for JLinkRTTLogger.

    The YAML file normally stores an RTT address as a hexadecimal string:

        rtt_address: '32070000'

    The logger expects:

        0x32070000

    Args:
        raw_address:
            RTT address read from YAML.

    Returns:
        tuple:
            A pair containing:

                raw_text:
                    Original normalized text used in log headers.

                command_address:
                    Address with a 0x prefix, or an empty string when no
                    address was configured.

    Raises:
        ValueError:
            If the address is not valid hexadecimal data.
    """
    if raw_address is None:
        return "", ""

    raw_text = str(raw_address).strip()

    if not raw_text:
        return "", ""

    if raw_text.lower().startswith("0x"):
        hexadecimal_part = raw_text[2:]
    else:
        hexadecimal_part = raw_text

    # Validate the address without changing its intended hexadecimal meaning.
    int(hexadecimal_part, 16)

    return raw_text, f"0x{hexadecimal_part}"


def terminate_process(process, wait_timeout=5):
    """
    Terminate a subprocess and wait for it to exit.

    If graceful termination does not complete within wait_timeout seconds,
    the process is killed.

    Args:
        process:
            subprocess.Popen object.

        wait_timeout (int):
            Maximum number of seconds to wait after terminate().
    """
    if process is None:
        return

    if process.poll() is not None:
        return

    try:
        process.terminate()
        process.wait(timeout=wait_timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    except Exception:
        # Cleanup must not hide the original test or programming result.
        pass


def read_new_binary_log(file_path, last_position):
    """
    Read newly appended bytes from a binary log file.

    Args:
        file_path (str):
            Path to the log file.

        last_position (int):
            Previous read position.

    Returns:
        tuple:
            (decoded_text, new_position)
    """
    if not os.path.exists(file_path):
        return "", last_position

    try:
        file_size = os.path.getsize(file_path)

        # Handle truncation or replacement of the log file.
        if file_size < last_position:
            last_position = 0

        if file_size == last_position:
            return "", last_position

        with open(file_path, "rb") as log_file:
            log_file.seek(last_position)
            new_bytes = log_file.read()
            new_position = log_file.tell()

        new_text = new_bytes.decode("utf-8", errors="replace")
        return new_text, new_position

    except OSError:
        return "", last_position


def read_new_text_log(file_path, last_position):
    """
    Read newly appended text from a tool output file.

    Args:
        file_path (str):
            Path to the tool output log.

        last_position (int):
            Previous read position.

    Returns:
        tuple:
            (new_text, new_position)
    """
    if not os.path.exists(file_path):
        return "", last_position

    try:
        file_size = os.path.getsize(file_path)

        if file_size < last_position:
            last_position = 0

        if file_size == last_position:
            return "", last_position

        with open(
            file_path,
            "r",
            encoding="utf-8",
            errors="replace",
        ) as tool_file:
            tool_file.seek(last_position)
            new_text = tool_file.read()
            new_position = tool_file.tell()

        return new_text, new_position

    except OSError:
        return "", last_position


def generate_jlink_script(
    script_path,
    flash_plan,
    interface_speed=4000,
):
    """
    Generate the J-Link Commander script.

    Generated TrustZone sequence:

        speed 4000
        r
        h
        loadfile "<SC image>"
        loadfile "<NS/NSC image>"
        r
        g
        q

    There is intentionally no reset, disconnect, or explicit erase command
    between the SC and NS/NSC "loadfile" commands.

    Args:
        script_path (str):
            Output J-Link Commander script path.

        flash_plan (list):
            Ordered list returned by create_flash_plan().

        interface_speed (int):
            SWD interface speed in kHz.
    """
    script_parent = os.path.dirname(os.path.abspath(script_path))
    os.makedirs(script_parent, exist_ok=True)

    with open(
        script_path,
        "w",
        encoding="utf-8",
        newline="\n",
    ) as script_file:
        script_file.write(f"speed {interface_speed}\n")

        # Reset and halt once before programming starts.
        script_file.write("r\n")
        script_file.write("h\n")

        # Flash images exactly in the order returned by create_flash_plan().
        #
        # For TZ:
        #   loadfile SC
        #   loadfile NS/NSC
        #
        # Do not insert "r", "erase", "exit", or reconnect operations here.
        for _, image_path in flash_plan:
            script_file.write(
                f"loadfile {quote_jlink_path(image_path)}\n"
            )

        # Reset only after every required image has been programmed.
        script_file.write("r\n")
        script_file.write("g\n")
        script_file.write("q\n")


def flash_has_error(flash_content, return_code):
    """
    Determine whether J-Link programming failed.

    Args:
        flash_content (str):
            Complete J-Link Commander output.

        return_code (int):
            J-Link Commander process return code.

    Returns:
        tuple:
            (failed, reason)
    """
    if return_code != 0:
        return (
            True,
            f"J-Link Commander exited with return code {return_code}",
        )

    lower_content = flash_content.lower()

    for keyword in FLASH_ERROR_KEYWORDS:
        if keyword.lower() in lower_content:
            error_line = next(
                (
                    line.strip()
                    for line in flash_content.splitlines()
                    if keyword.lower() in line.lower()
                ),
                keyword,
            )

            return True, error_line

    return False, ""


def execute_jlink_workflow(
    jlink_path,
    rtt_logger_path,
    info_path,
    script_path,
    log_path,
    log_acc_path,
    part_number,
    ip,
    logger_timeout_sec,
    run_specified_build,
    log_dir_path,
):
    """
    Parse YAML, flash configured images, execute tests, and collect RTT logs.

    TrustZone programming flow:

        1. Validate SC and NS/NSC files.
        2. Connect J-Link.
        3. Reset and halt.
        4. Flash SC image(s).
        5. Flash NS/NSC application.
        6. Reset and start the target.
        7. Connect RTT Logger.
        8. Capture test output.

    Args:
        jlink_path (str):
            Path to JLinkExe.

        rtt_logger_path (str):
            Path to JLinkRTTLoggerExe.

        info_path (str):
            YAML test information path.

        script_path (str):
            Temporary J-Link Commander script path.

        log_path (str):
            Temporary target RTT log path.

        log_acc_path (str):
            Accumulated RTT output path.

        part_number (str):
            J-Link target device name.

        ip (str):
            J-Link IP address. Empty means use USB.

        logger_timeout_sec (int):
            RTT collection timeout.

        run_specified_build (str):
            Exact application path to run. Empty means run every build.

        log_dir_path (str):
            Directory for individual flash and execution logs.
    """
    # -------------------------------------------------------------------------
    # Validate main inputs
    # -------------------------------------------------------------------------

    if not os.path.isfile(jlink_path):
        print(f"[ERROR] J-Link executable does not exist: {jlink_path}")
        return

    if not os.path.isfile(rtt_logger_path):
        print(
            f"[ERROR] J-Link RTT Logger executable does not exist: "
            f"{rtt_logger_path}"
        )
        return

    if not os.path.isfile(info_path):
        print(f"[ERROR] YAML configuration does not exist: {info_path}")
        return

    # -------------------------------------------------------------------------
    # Prepare output files
    # -------------------------------------------------------------------------

    # Preserve the original behavior: remove logs from the previous invocation.
    #
    # This only deletes PC log files. It does not erase target flash memory.
    if os.path.exists(log_dir_path):
        shutil.rmtree(log_dir_path)

    os.makedirs(log_dir_path, exist_ok=True)

    if os.path.exists(log_path):
        os.remove(log_path)

    if os.path.exists(log_acc_path):
        os.remove(log_acc_path)

    accumulated_log_parent = os.path.dirname(
        os.path.abspath(log_acc_path)
    )
    os.makedirs(accumulated_log_parent, exist_ok=True)

    summary_list = []

    # -------------------------------------------------------------------------
    # Load YAML configuration
    # -------------------------------------------------------------------------

    try:
        with open(
            info_path,
            "r",
            encoding="utf-8",
        ) as yaml_file:
            data = yaml.safe_load(yaml_file)

    except (OSError, yaml.YAMLError) as error:
        print(
            f"[ERROR] Failed to read YAML configuration "
            f"'{info_path}': {error}"
        )
        return

    if not data:
        print(f"[ERROR] YAML configuration is empty: {info_path}")
        return

    if not isinstance(data, dict):
        print("[ERROR] Top-level YAML data must be a dictionary.")
        return

    # -------------------------------------------------------------------------
    # Process every test configuration
    # -------------------------------------------------------------------------

    for category_name, category_data in data.items():
        if not isinstance(category_data, dict):
            continue

        for config_name, config_data in category_data.items():
            if not isinstance(config_data, dict):
                continue

            projects = config_data.get("projects", [])

            if not projects:
                continue

            if not isinstance(projects, list):
                print(
                    f"[ERROR] 'projects' must be a list for "
                    f"[{category_name}] {config_name}"
                )
                continue

            # Preserve the original behavior: use the first project.
            project = projects[0]

            if not isinstance(project, dict):
                print(
                    f"[ERROR] Invalid project configuration for "
                    f"[{category_name}] {config_name}"
                )
                continue

            app_path = str(project.get("application", "")).strip()

            # Run only the explicitly selected application when requested.
            if (
                run_specified_build
                and run_specified_build != app_path
            ):
                continue

            # -----------------------------------------------------------------
            # Parse and validate the RTT address
            # -----------------------------------------------------------------

            try:
                rtt_addr_raw, rtt_addr = normalize_rtt_address(
                    project.get("rtt_address", "")
                )
            except ValueError:
                error_message = (
                    f"Invalid RTT address "
                    f"'{project.get('rtt_address', '')}'"
                )

                print(
                    f"[ERROR] {error_message} for "
                    f"[{category_name}] {config_name}"
                )

                summary_list.append(
                    f"FAILED ({error_message}) "
                    f"| BUILD: {app_path} "
                    f"| CATEGORY: {category_name}"
                )
                continue

            # -----------------------------------------------------------------
            # Build and validate the flash plan
            # -----------------------------------------------------------------

            try:
                is_tz_build, flash_plan = create_flash_plan(
                    category_name,
                    project,
                )
            except (ValueError, FileNotFoundError) as error:
                print(
                    f"[ERROR] Invalid flash configuration for "
                    f"[{category_name}] {config_name}: {error}"
                )

                summary_list.append(
                    f"FAILED ({error}) "
                    f"| BUILD: {app_path} "
                    f"| CATEGORY: {category_name}"
                )
                continue

            safe_category = sanitize_filename(category_name)
            safe_config = sanitize_filename(config_name)
            log_prefix = f"{safe_category}_{safe_config}"

            flash_log_file = os.path.join(
                log_dir_path,
                f"{log_prefix}_flash.log",
            )

            exec_log_file = os.path.join(
                log_dir_path,
                f"{log_prefix}_exec.log",
            )

            logger_stdout_file = os.path.join(
                log_dir_path,
                f"{log_prefix}_rtt_tool.log",
            )

            # -----------------------------------------------------------------
            # Generate the J-Link Commander script
            # -----------------------------------------------------------------

            try:
                generate_jlink_script(
                    script_path=script_path,
                    flash_plan=flash_plan,
                    interface_speed=4000,
                )
            except OSError as error:
                print(
                    f"[ERROR] Failed to create J-Link script "
                    f"'{script_path}': {error}"
                )

                summary_list.append(
                    f"FAILED (Cannot create J-Link script: {error}) "
                    f"| BUILD: {app_path} "
                    f"| CATEGORY: {category_name}"
                )
                continue

            # -----------------------------------------------------------------
            # Construct J-Link Commander command
            # -----------------------------------------------------------------

            flash_cmd = [jlink_path]

            if ip:
                flash_cmd.extend(["-ip", ip])

            flash_cmd.extend([
                "-device",
                part_number,
                "-if",
                "SWD",
                "-speed",
                "4000",
                "-autoconnect",
                "1",
                "-CommanderScript",
                script_path,
            ])

            print("\n\n============================================================")
            print(
                f"--- Flashing device for "
                f"[{category_name}] {config_name} ---"
            )

            # Details are stored in the flash log without adding extra console
            # lines that would change the requested output format.
            try:
                with open(
                    flash_log_file,
                    "w",
                    encoding="utf-8",
                    errors="replace",
                ) as flash_out:
                    flash_out.write(
                        f"Build type: "
                        f"{'TZ' if is_tz_build else 'Standard'}\n"
                    )
                    flash_out.write("Flash plan:\n")

                    for index, (image_type, image_path) in enumerate(
                        flash_plan,
                        start=1,
                    ):
                        flash_out.write(
                            f"  {index}. {image_type}: {image_path}\n"
                        )

                    flash_out.write("\n=== J-LINK COMMANDER OUTPUT ===\n")
                    flash_out.flush()

                    flash_process = subprocess.Popen(
                        flash_cmd,
                        stdout=flash_out,
                        stderr=subprocess.STDOUT,
                    )

                    flash_start_time = time.time()
                    last_read_position = 0
                    current_status = "Connecting & Initializing..."
                    estimated_percentage = 0

                    while flash_process.poll() is None:
                        elapsed = int(
                            time.time() - flash_start_time
                        )

                        new_content, last_read_position = (
                            read_new_text_log(
                                flash_log_file,
                                last_read_position,
                            )
                        )

                        if new_content:
                            for (
                                keyword,
                                phase,
                                percentage,
                            ) in FLASH_DETECTION_LIST:
                                if keyword in new_content:
                                    current_status = phase
                                    estimated_percentage = percentage

                        status_message = (
                            f"    -> [{estimated_percentage:3d}%] "
                            f"{current_status} ({elapsed}s)"
                        )

                        sys.stdout.write(
                            f"\r{status_message:<100}"
                        )
                        sys.stdout.flush()
                        time.sleep(0.3)

                    return_code = flash_process.wait()

            except OSError as error:
                print(
                    f"\n[ERROR] Failed to start J-Link Commander: {error}"
                )

                summary_list.append(
                    f"FAILED (Cannot start J-Link Commander: {error}) "
                    f"| BUILD: {app_path} "
                    f"| CATEGORY: {category_name}"
                )
                continue

            total_flash_time = int(
                time.time() - flash_start_time
            )

            # Read the complete flash output after the J-Link process exits.
            try:
                with open(
                    flash_log_file,
                    "r",
                    encoding="utf-8",
                    errors="replace",
                ) as flash_file:
                    flash_content = flash_file.read()
            except OSError:
                flash_content = ""

            flash_failed, flash_error = flash_has_error(
                flash_content,
                return_code,
            )

            if flash_failed:
                failure_message = (
                    f"    -> [FAILED] Flashing failed in "
                    f"{total_flash_time}s: {flash_error}"
                )
                sys.stdout.write(f"\r{failure_message:<100}\n")
                sys.stdout.flush()

                summary_list.append(
                    f"FAILED (Flash: {flash_error}) "
                    f"| BUILD: {app_path} "
                    f"| CATEGORY: {category_name}"
                )

                # Do not start RTT when programming failed.
                with open(
                    log_acc_path,
                    "a",
                    encoding="utf-8",
                ) as accumulated_file:
                    accumulated_file.write(
                        "###################### "
                        f"Flash Info: SREC={app_path} "
                        f"| RTTAddress={rtt_addr_raw} "
                        f"| Category={category_name} "
                        f"| Result=FAILED "
                        "######################\n"
                    )
                    accumulated_file.write(flash_content)
                    accumulated_file.write("\n\n")

                continue

            done_message = (
                f"    -> [100%] Flashing completed successfully "
                f"in {total_flash_time}s."
            )
            sys.stdout.write(f"\r{done_message:<100}\n")
            sys.stdout.flush()

            # -----------------------------------------------------------------
            # Prepare RTT Logger
            # -----------------------------------------------------------------

            if os.path.exists(log_path):
                os.remove(log_path)

            log_cmd = [rtt_logger_path]

            if ip:
                log_cmd.extend(["-ip", ip])

            log_cmd.extend([
                "-device",
                part_number,
                "-if",
                "SWD",
                "-speed",
                "4000",
            ])

            if rtt_addr:
                log_cmd.extend([
                    "-RTTAddress",
                    rtt_addr,
                ])

            log_cmd.extend([
                "-RTTChannel",
                "0",
                log_path,
            ])

            print(
                f"--- Starting execution for "
                f"[{category_name}] {config_name} ---"
            )
            print(
                "============================================================\n"
            )

            current_log = ""
            current_tool_log = ""
            timeout_occurred = False
            terminate_early = False
            execution_status = ""
            triggered_errors = set()
            logger_process = None
            tool_output = None

            target_last_position = 0
            tool_last_position = 0

            try:
                tool_output = open(
                    logger_stdout_file,
                    "w",
                    encoding="utf-8",
                    errors="replace",
                )

                logger_process = subprocess.Popen(
                    log_cmd,
                    stdout=tool_output,
                    stderr=subprocess.STDOUT,
                )

                start_time = time.time()

                while True:
                    process_exited = (
                        logger_process.poll() is not None
                    )

                    # Read newly generated target RTT output.
                    new_target_data, target_last_position = (
                        read_new_binary_log(
                            log_path,
                            target_last_position,
                        )
                    )

                    if new_target_data:
                        print(
                            new_target_data,
                            end="",
                            flush=True,
                        )
                        current_log += new_target_data

                    # Flush the tool output handle so data becomes visible to
                    # the reader as soon as possible.
                    try:
                        tool_output.flush()
                    except Exception:
                        pass

                    new_tool_data, tool_last_position = (
                        read_new_text_log(
                            logger_stdout_file,
                            tool_last_position,
                        )
                    )

                    if new_tool_data:
                        current_tool_log += new_tool_data

                    combined_log = (
                        current_log
                        + "\n"
                        + current_tool_log
                    )

                    # Detect RTT Logger or connection errors.
                    for keyword, error_status in EXEC_DETECTION_LIST:
                        if (
                            keyword in combined_log
                            and keyword not in triggered_errors
                        ):
                            triggered_errors.add(keyword)

                            error_line = next(
                                (
                                    line
                                    for line in combined_log.splitlines()
                                    if keyword in line
                                ),
                                keyword,
                            )

                            print(
                                f"\n[ERROR DETECTED] {error_line}"
                            )

                            execution_status = (
                                f"FAILED ({error_status})"
                            )
                            terminate_early = True
                            terminate_process(logger_process)
                            break

                    if terminate_early:
                        break

                    # Normal test completion.
                    if "FSP TESTS ALLDONE" in current_log:
                        time.sleep(0.5)

                        # Read any remaining RTT output before stopping.
                        final_target_data, target_last_position = (
                            read_new_binary_log(
                                log_path,
                                target_last_position,
                            )
                        )

                        if final_target_data:
                            print(
                                final_target_data,
                                end="",
                                flush=True,
                            )
                            current_log += final_target_data

                        terminate_process(logger_process)
                        break

                    # Timeout handling.
                    if (
                        time.time() - start_time
                        > logger_timeout_sec
                    ):
                        print(
                            f"\n[TIMEOUT] Execution exceeded "
                            f"{logger_timeout_sec} seconds. "
                            f"Terminating...\n"
                        )

                        timeout_occurred = True
                        terminate_process(logger_process)
                        break

                    # If the logger exits before the target completion marker,
                    # collect its final output and report a failure.
                    if process_exited:
                        final_target_data, target_last_position = (
                            read_new_binary_log(
                                log_path,
                                target_last_position,
                            )
                        )

                        final_tool_data, tool_last_position = (
                            read_new_text_log(
                                logger_stdout_file,
                                tool_last_position,
                            )
                        )

                        if final_target_data:
                            print(
                                final_target_data,
                                end="",
                                flush=True,
                            )
                            current_log += final_target_data

                        if final_tool_data:
                            current_tool_log += final_tool_data

                        if "FSP TESTS ALLDONE" not in current_log:
                            execution_status = (
                                "FAILED "
                                "(RTT Logger Exited Unexpectedly)"
                            )

                        break

                    time.sleep(0.2)

            except OSError as error:
                execution_status = (
                    f"FAILED (Cannot start RTT Logger: {error})"
                )
                print(f"\n[ERROR] {execution_status}")

            finally:
                terminate_process(logger_process)

                if tool_output is not None:
                    try:
                        tool_output.close()
                    except Exception:
                        pass

                # Perform one final read after closing RTT Logger.
                final_target_data, target_last_position = (
                    read_new_binary_log(
                        log_path,
                        target_last_position,
                    )
                )

                final_tool_data, tool_last_position = (
                    read_new_text_log(
                        logger_stdout_file,
                        tool_last_position,
                    )
                )

                if final_target_data:
                    print(
                        final_target_data,
                        end="",
                        flush=True,
                    )
                    current_log += final_target_data

                if final_tool_data:
                    current_tool_log += final_tool_data

            # -----------------------------------------------------------------
            # Save individual execution log
            # -----------------------------------------------------------------

            try:
                with open(
                    exec_log_file,
                    "w",
                    encoding="utf-8",
                ) as execution_file:
                    execution_file.write(
                        "=== BUILD INFORMATION ===\n"
                    )
                    execution_file.write(
                        f"Category: {category_name}\n"
                    )
                    execution_file.write(
                        f"Configuration: {config_name}\n"
                    )
                    execution_file.write(
                        f"Application: {app_path}\n"
                    )
                    execution_file.write(
                        f"Build type: "
                        f"{'TZ' if is_tz_build else 'Standard'}\n"
                    )
                    execution_file.write(
                        f"RTT address: {rtt_addr_raw}\n"
                    )

                    execution_file.write(
                        "\n=== FLASH PLAN ===\n"
                    )

                    for index, (image_type, image_path) in enumerate(
                        flash_plan,
                        start=1,
                    ):
                        execution_file.write(
                            f"{index}. {image_type}: {image_path}\n"
                        )

                    execution_file.write(
                        "\n=== TOOL STDOUT/STDERR ===\n"
                    )
                    execution_file.write(current_tool_log)

                    execution_file.write(
                        "\n=== TARGET RTT LOG ===\n"
                    )
                    execution_file.write(current_log)

            except OSError as error:
                print(
                    f"[WARNING] Failed to write execution log "
                    f"'{exec_log_file}': {error}"
                )

            # -----------------------------------------------------------------
            # Determine test summary
            # -----------------------------------------------------------------

            if timeout_occurred:
                summary_line = "TEST TIMED OUT"

            elif execution_status:
                summary_line = execution_status

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

            # -----------------------------------------------------------------
            # Append the current test output to the global log
            # -----------------------------------------------------------------

            try:
                with open(
                    log_acc_path,
                    "a",
                    encoding="utf-8",
                ) as accumulated_file:
                    accumulated_file.write(
                        "###################### "
                        f"Flash Info: SREC={app_path} "
                        f"| RTTAddress={rtt_addr_raw} "
                        f"| Category={category_name} "
                        f"| Type="
                        f"{'TZ' if is_tz_build else 'Standard'} "
                        "######################\n"
                    )

                    accumulated_file.write(
                        "=== FLASH PLAN ===\n"
                    )

                    for index, (image_type, image_path) in enumerate(
                        flash_plan,
                        start=1,
                    ):
                        accumulated_file.write(
                            f"{index}. {image_type}: {image_path}\n"
                        )

                    accumulated_file.write(
                        "\n=== TOOL STDOUT/STDERR ===\n"
                    )
                    accumulated_file.write(current_tool_log)

                    accumulated_file.write(
                        "\n=== TARGET RTT LOG ===\n"
                    )
                    accumulated_file.write(current_log)
                    accumulated_file.write("\n\n")

            except OSError as error:
                print(
                    f"[WARNING] Failed to append global log "
                    f"'{log_acc_path}': {error}"
                )

            # Remove only the temporary RTT output file.
            #
            # Individual flash, execution, and RTT tool logs remain in
            # LOG_DIR_PATH.
            try:
                os.remove(log_path)
            except OSError:
                pass

    # -------------------------------------------------------------------------
    # Print final summary
    # -------------------------------------------------------------------------

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


def main():
    """
    Parse command-line arguments and execute the J-Link workflow.
    """
    parser = argparse.ArgumentParser(
        description=(
            "Flash FSP tests and capture RTT output using SEGGER "
            "J-Link command-line tools."
        )
    )

    parser.add_argument(
        "-JLINK_PATH",
        type=str,
        default=JLINK_PATH,
        help="Path to JLinkExe.",
    )

    parser.add_argument(
        "-RTT_LOGGER_PATH",
        type=str,
        default=RTT_LOGGER_PATH,
        help="Path to JLinkRTTLoggerExe.",
    )

    parser.add_argument(
        "-PATH_TEST_INFO",
        type=str,
        default=PATH_TEST_INFO,
        help="Path to the YAML test configuration.",
    )

    parser.add_argument(
        "-PATH_JLINK_SCRIPT",
        type=str,
        default=PATH_JLINK_SCRIPT,
        help="Temporary J-Link Commander script path.",
    )

    parser.add_argument(
        "-PATH_JLINK_LOG",
        type=str,
        default=PATH_JLINK_LOG,
        help="Temporary target RTT log path.",
    )

    parser.add_argument(
        "-PATH_JLINK_LOG_ACC",
        type=str,
        default=PATH_JLINK_LOG_ACC,
        help="Accumulated test log path.",
    )

    parser.add_argument(
        "-DEVICE_PART_NUMBER",
        type=str,
        default=DEVICE_PART_NUMBER,
        help="J-Link target device name.",
    )

    parser.add_argument(
        "-DEVICE_IP",
        type=str,
        default=DEVICE_IP,
        help=(
            "Remote J-Link IP address. Use an empty string for a local "
            "USB J-Link."
        ),
    )

    parser.add_argument(
        "-LOGGER_TIMEOUT_SEC",
        type=int,
        default=LOGGER_TIMEOUT_SEC,
        help="RTT Logger timeout in seconds.",
    )

    parser.add_argument(
        "-RUN_SPECIFIED_BUILD",
        type=str,
        default=RUN_SPECIFIED_BUILD,
        help=(
            "Run only the project whose application path exactly matches "
            "this value."
        ),
    )

    parser.add_argument(
        "-LOG_DIR_PATH",
        type=str,
        default=LOG_DIR_PATH,
        help="Directory for individual flash and execution logs.",
    )

    args = parser.parse_args()

    # Display the effective configuration.
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

    if args.LOGGER_TIMEOUT_SEC <= 0:
        parser.error("-LOGGER_TIMEOUT_SEC must be greater than zero")

    execute_jlink_workflow(
        jlink_path=args.JLINK_PATH,
        rtt_logger_path=args.RTT_LOGGER_PATH,
        info_path=args.PATH_TEST_INFO,
        script_path=args.PATH_JLINK_SCRIPT,
        log_path=args.PATH_JLINK_LOG,
        log_acc_path=args.PATH_JLINK_LOG_ACC,
        part_number=args.DEVICE_PART_NUMBER,
        ip=args.DEVICE_IP,
        logger_timeout_sec=args.LOGGER_TIMEOUT_SEC,
        run_specified_build=args.RUN_SPECIFIED_BUILD,
        log_dir_path=args.LOG_DIR_PATH,
    )


if __name__ == "__main__":
    main()
