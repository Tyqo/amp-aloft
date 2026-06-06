Add-Type @"
using System;
using System.Threading.Tasks;
using System.Runtime.InteropServices;

public class ProcessManager {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);
    
    [DllImport("kernel32.dll")]
    private static extern bool SetInformationJobObject(IntPtr hJob, int JobObjectInfoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);
    
    [DllImport("kernel32.dll")]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    private IntPtr jobHandle;

    public ProcessManager() {
        jobHandle = CreateJobObject(IntPtr.Zero, null);
        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = 0x2000;
        
        var length = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        var infoPtr = Marshal.AllocHGlobal(length);
        Marshal.StructureToPtr(info, infoPtr, false);
        
        SetInformationJobObject(jobHandle, 9, infoPtr, (uint)length);
        Marshal.FreeHGlobal(infoPtr);
    }

    public void AddProcess(IntPtr processHandle) {
        AssignProcessToJobObject(jobHandle, processHandle);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public Int64 PerProcessUserTimeLimit;
        public Int64 PerJobUserTimeLimit;
        public UInt32 LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public UInt32 ActiveProcessLimit;
        public Int64 Affinity;
        public UInt32 PriorityClass;
        public UInt32 SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS {
        public UInt64 ReadOperationCount;
        public UInt64 WriteOperationCount;
        public UInt64 OtherOperationCount;
        public UInt64 ReadTransferCount;
        public UInt64 WriteTransferCount;
        public UInt64 OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }
}
"@

$pm = New-Object ProcessManager
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = ".\Aloft.exe"
$psi.Arguments = "-batchmode -nographics -server load#MAPNAME# servername#ALOFTSERVER# log#ERROR# isvisible#true# playercount#8# serverport#0# admin#-1# admin#-2#"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true

# Initialize variables
$logBuffer = [System.Collections.ArrayList]@()
$bufferSize = 15  # Adjust this value as needed
$logFile = "output.txt" 

# Configure the process to redirect standard output
$psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false

# Start the process
$process = [System.Diagnostics.Process]::Start($psi)

# Add the process handle to your custom process manager
$pm.AddProcess($process.Handle)


# Backup existing log file if it exists
if (Test-Path $logFile) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupName = [System.IO.Path]::GetFileNameWithoutExtension($logFile) + 
                     "_$timestamp" +
                     [System.IO.Path]::GetExtension($logFile)
        
        # Simply rename the existing file
        Rename-Item -Path $logFile -NewName $backupName -Force
}

function Flush-LogBuffer {
    param (
        [Parameter(Mandatory)]
        [System.Collections.ArrayList]$Buffer,
        [Parameter(Mandatory)]
        [string]$LogFile
    )
    
    if ($Buffer.Count -gt 0) {
        $Buffer -join "`n" | Out-File -Append -FilePath $LogFile
        $Buffer.Clear()
    }
}

# Process output while the process is running
while (!$process.HasExited) {
    $line = $process.StandardOutput.ReadLine()
    if ($line) {
        # Display processed lines that start with '#'
        if ($line.StartsWith("#")) {
            # Add the line to the buffer
            [void]$logBuffer.Add($line)
            Write-Host $line.Substring(1)
        }
        
        # Flush the buffer to the log file when the buffer size is reached
        if ($logBuffer.Count -ge $bufferSize) {
            Flush-LogBuffer -Buffer $logBuffer -LogFile $logFile
        }
    }
}

# Flush any remaining lines in the buffer
Flush-LogBuffer -Buffer $logBuffer -LogFile $logFile
