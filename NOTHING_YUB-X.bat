<# :
@echo off
title NOTHING YUB-X LOADER
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0') -join [Environment]::NewLine)"
exit /b
#>

# Force TLS 1.2 and TLS 1.3 for secure downloads
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "             NOTHING YUB-X SYSTEM LOADER          " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Function to search for yubx-ui.exe on system drive and stop on first find
function Find-FirstYubxUI {
    $sysDrive = $env:SystemDrive + "\"
    Write-Host "[*] Scanning system drive ($sysDrive) for yubx-ui.exe (stops on first match)..." -ForegroundColor Yellow
    
    $foundPath = $null
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($sysDrive)
    
    # Exclude system folders to optimize speed
    $excludeFolders = @(
        "Windows", "System Volume Information", "`$Recycle.Bin", "`$Recycle", "Recovery", 
        "Microsoft", "Package Cache", "Config.Msi", "boot", "System32"
    )
    
    while ($queue.Count -gt 0 -and $null -eq $foundPath) {
        $currentDir = $queue.Dequeue()
        
        # Check files in the current folder
        $files = @()
        try {
            $files = [System.IO.Directory]::GetFiles($currentDir, "*.exe")
        } catch {}
        
        foreach ($file in $files) {
            $fileName = [System.IO.Path]::GetFileName($file)
            $originalName = ""
            try {
                $originalName = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file).OriginalFilename
            } catch {}
            
            if ($fileName -ieq "yubx-ui.exe" -or $originalName -ieq "yubx-ui.exe") {
                $foundPath = $file
                break
            }
        }
        
        if ($null -ne $foundPath) {
            break
        }
        
        # Get subdirectories
        $subDirs = @()
        try {
            $subDirs = [System.IO.Directory]::GetDirectories($currentDir)
        } catch {}
        
        foreach ($sub in $subDirs) {
            $subName = [System.IO.Path]::GetFileName($sub)
            $exclude = $false
            foreach ($ex in $excludeFolders) {
                if ($subName -ieq $ex -or $subName -like "*$ex*") {
                    $exclude = $true
                    break
                }
            }
            
            if (-not $exclude) {
                $queue.Enqueue($sub)
            }
        }
    }
    
    if ($null -ne $foundPath) {
        $origInfo = ""
        try {
            $origName = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($foundPath).OriginalFilename
            if ($origName -and $origName -ine [System.IO.Path]::GetFileName($foundPath)) {
                $origInfo = " (Renamed from: $origName)"
            }
        } catch {}
        Write-Host "[+] Found yubx-ui.exe at: $foundPath$origInfo" -ForegroundColor Green
    } else {
        Write-Host "[-] yubx-ui.exe was not found on the system drive." -ForegroundColor Yellow
    }
    Write-Host ""
}

# Run first search
Find-FirstYubxUI

# Determine and setup bin directory
$binDir = Join-Path $env:APPDATA "com.YUB-X.ui\YUB-X UI\bin"
Write-Host "[*] Checking target bin directory: $binDir" -ForegroundColor Yellow

if (-not (Test-Path $binDir)) {
    Write-Host "[*] Directory structure not found. Creating directories..." -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Write-Host "[+] Directory successfully created." -ForegroundColor Green
    } catch {
        Write-Host "[!] Critical Error: Failed to create directory: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Press any key to exit..."
        try {
            $null = [System.Console]::ReadKey($true)
        } catch {
            $null = Read-Host
        }
        exit
    }
} else {
    Write-Host "[+] Target bin directory exists." -ForegroundColor Green
}
Write-Host ""

# Clean files in the bin folder and list deleted names
Write-Host "[*] Cleaning bin directory..." -ForegroundColor Yellow
$binFiles = Get-ChildItem -Path $binDir -File -Recurse -Force -ErrorAction SilentlyContinue
if ($binFiles.Count -gt 0) {
    foreach ($file in $binFiles) {
        Write-Host "    [-] Deleting: $($file.Name)" -ForegroundColor DarkYellow
        try {
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
        } catch {
            Write-Host "    [!] Failed to delete $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "[+] Cleaning completed." -ForegroundColor Green
} else {
    Write-Host "[+] Bin directory is already empty." -ForegroundColor Green
}
Write-Host ""

# Function to download files with retries and a progress bar
function Download-FileWithProgress {
    param(
        [string]$url,
        [string]$outputPath,
        [int]$maxRetries = 5
    )
    
    $fileName = Split-Path $outputPath -Leaf
    
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        Write-Host "[*] Downloading $fileName (Attempt $attempt of $maxRetries)..." -ForegroundColor Yellow
        
        $response = $null
        $inputStream = $null
        $outputStream = $null
        
        try {
            $request = [System.Net.HttpWebRequest]::Create($url)
            $request.Timeout = 30000
            $request.Method = "GET"
            
            $response = $request.GetResponse()
            $totalBytes = $response.ContentLength
            if ($null -eq $totalBytes -or $totalBytes -lt 0) {
                $totalBytes = 0
            }
            
            $inputStream = $response.GetResponseStream()
            $outputStream = [System.IO.File]::Create($outputPath)
            
            $buffer = New-Object byte[] 8192
            $bytesRead = 0
            $totalBytesRead = 0
            $progressBarWidth = 30
            
            while (($bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $outputStream.Write($buffer, 0, $bytesRead)
                $totalBytesRead += $bytesRead
                
                if ($totalBytes -gt 0) {
                    $percent = [math]::Floor(($totalBytesRead / $totalBytes) * 100)
                    $filled = [math]::Floor(($totalBytesRead / $totalBytes) * $progressBarWidth)
                    $unfilled = $progressBarWidth - $filled
                    
                    if ($filled -lt 0) { $filled = 0 }
                    if ($unfilled -lt 0) { $unfilled = 0 }
                    
                    $bar = ("#" * $filled) + ("-" * $unfilled)
                    $msg = "`r    Progress: [$bar] $percent% ($([math]::Round($totalBytesRead/1KB)) KB / $([math]::Round($totalBytes/1KB)) KB)"
                    Write-Host -NoNewline $msg -ForegroundColor Cyan
                } else {
                    $msg = "`r    Progress: $([math]::Round($totalBytesRead/1KB)) KB downloaded"
                    Write-Host -NoNewline $msg -ForegroundColor Cyan
                }
            }
            
            $outputStream.Close()
            $inputStream.Close()
            $response.Close()
            
            # End line for progress bar
            Write-Host ""
            
            if (Test-Path $outputPath) {
                $size = (Get-Item $outputPath).Length
                if ($size -gt 0) {
                    Write-Host "[+] Successfully downloaded and verified $fileName ($([math]::Round($size/1KB)) KB)" -ForegroundColor Green
                    return $true
                }
            }
            throw "Downloaded file is empty."
            
        } catch {
            if ($null -ne $outputStream) { try { $outputStream.Close() } catch {} }
            if ($null -ne $inputStream) { try { $inputStream.Close() } catch {} }
            if ($null -ne $response) { try { $response.Close() } catch {} }
            
            Write-Host ""
            Write-Host "[!] Attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Red
            if (Test-Path $outputPath) { Remove-Item $outputPath -Force | Out-Null }
            Start-Sleep -Seconds 2
        }
    }
    
    return $false
}

# Run downloads
$baseUrl = "https://github.com/nothingff0/HTTP/raw/refs/heads/main/"
$filesToDownload = @("Loader.exe", "injector.exe", "v", "yubx.dll")
$allDownloaded = $true

foreach ($file in $filesToDownload) {
    $url = $baseUrl + $file
    $outputPath = Join-Path $binDir $file
    $success = Download-FileWithProgress -url $url -outputPath $outputPath
    if (-not $success) {
        $allDownloaded = $false
    }
}

Write-Host ""
if ($allDownloaded) {
    Write-Host "[+] Verification SUCCESS: All files successfully downloaded." -ForegroundColor Green
} else {
    Write-Host "[!] Verification WARNING: One or more files failed to download." -ForegroundColor Red
}
Write-Host ""

# Post-download verification check for yubx-ui.exe in bin
Write-Host "[*] Checking if yubx-ui.exe is present in bin..." -ForegroundColor Yellow
$binExes = Get-ChildItem -Path $binDir -Filter *.exe -File -Force
$foundBinUI = $false
foreach ($exe in $binExes) {
    $orig = ""
    try { $orig = $exe.VersionInfo.OriginalFilename } catch {}
    if ($exe.Name -ieq "yubx-ui.exe" -or $orig -ieq "yubx-ui.exe") {
        Write-Host "[+] Verified: yubx-ui.exe exists in bin at: $($exe.FullName)" -ForegroundColor Green
        $foundBinUI = $true
    }
}
if (-not $foundBinUI) {
    Write-Host "[-] Note: yubx-ui.exe was not found directly in the downloaded bin folder." -ForegroundColor Yellow
}
Write-Host ""

# Function to search for RobloxPlayerBeta.exe (checks entire AppData\Local recursively with hidden files included)
function Find-Roblox {
    Write-Host "[*] Scanning system for RobloxPlayerBeta.exe (scanning entire AppData\Local recursively, including hidden files)..." -ForegroundColor Yellow
    $robloxPaths = [System.Collections.Generic.List[string]]::new()
    
    # Scan all user directories' Local AppData folder recursively
    $userDirs = Get-ChildItem -Path "C:\Users" -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "Public|Default|All Users" }
    $searchRoots = [System.Collections.Generic.List[string]]::new()
    
    foreach ($ud in $userDirs) {
        $path = Join-Path $ud.FullName "AppData\Local"
        if (Test-Path $path) {
            $searchRoots.Add($path)
        }
    }
    
    # Add Program Files paths
    if ($env:ProgramFiles) {
        $pf = Join-Path $env:ProgramFiles "Roblox"
        if (Test-Path $pf) { $searchRoots.Add($pf) }
    }
    if (${env:ProgramFiles(x86)}) {
        $pf86 = Join-Path ${env:ProgramFiles(x86)} "Roblox"
        if (Test-Path $pf86) { $searchRoots.Add($pf86) }
    }
    
    foreach ($root in $searchRoots) {
        # Recurse and include hidden/system files using -Force
        $files = Get-ChildItem -Path $root -Filter RobloxPlayerBeta.exe -Recurse -File -Force -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            if ($robloxPaths -notcontains $f.FullName) {
                $robloxPaths.Add($f.FullName)
            }
        }
    }
    
    return $robloxPaths
}

# Function to select path using Arrow keys / WS keys
function Select-RobloxPath {
    param(
        [string[]]$paths
    )
    
    $selectedIndex = 0
    $running = $true
    
    # Hide cursor
    $originalCursorSize = 25
    try {
        $originalCursorSize = $Host.UI.RawUI.CursorSize
        $Host.UI.RawUI.CursorSize = 0
    } catch {}
    
    $startPosition = $null
    try {
        $startPosition = $Host.UI.RawUI.CursorPosition
    } catch {}
    
    while ($running) {
        if ($null -ne $startPosition) {
            try { $Host.UI.RawUI.CursorPosition = $startPosition } catch {}
        }
        
        Write-Host "Multiple Roblox installations found. Choose which one to run:" -ForegroundColor Green
        for ($i = 0; $i -lt $paths.Count; $i++) {
            if ($i -eq $selectedIndex) {
                Write-Host "  [>] [*] $($paths[$i])" -ForegroundColor Cyan
            } else {
                Write-Host "  [ ] [*] $($paths[$i])" -ForegroundColor White
            }
        }
        if ($selectedIndex -eq $paths.Count) {
            Write-Host "  [>] Skip running Roblox" -ForegroundColor Cyan
        } else {
            Write-Host "  [ ] Skip running Roblox" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "Use Up/Down Arrow keys or W/S keys to navigate. Press Enter to select." -ForegroundColor DarkGray
        
        # ReadKey fallback for non-interactive hosts
        $keyInfo = $null
        try {
            $keyInfo = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        } catch {
            Write-Host "[!] Console ReadKey not supported in this host. Defaulting to skip." -ForegroundColor Red
            return $paths.Count
        }
        
        $key = $keyInfo.Character
        $virtualKey = $keyInfo.VirtualKeyCode
        
        if ($virtualKey -eq 38 -or $key -eq 'w' -or $key -eq 'W') { # Up Arrow / W
            $selectedIndex--
            if ($selectedIndex -lt 0) {
                $selectedIndex = $paths.Count
            }
        } elseif ($virtualKey -eq 40 -or $key -eq 's' -or $key -eq 'S') { # Down Arrow / S
            $selectedIndex++
            if ($selectedIndex -gt $paths.Count) {
                $selectedIndex = 0
            }
        } elseif ($virtualKey -eq 13) { # Enter
            $running = $false
        }
    }
    
    try {
        $Host.UI.RawUI.CursorSize = $originalCursorSize
    } catch {}
    
    Write-Host ""
    return $selectedIndex
}

# Scan Roblox (Do not ask Y/N before scanning)
$robloxPaths = @(Find-Roblox)

$selectedPath = $null
$shouldRun = $false

if ($robloxPaths.Count -eq 0) {
    Write-Host "[-] RobloxPlayerBeta.exe was not found on this computer." -ForegroundColor Red
} elseif ($robloxPaths.Count -eq 1) {
    $selectedPath = $robloxPaths[0]
    Write-Host "[*] Found Roblox installation at: $selectedPath" -ForegroundColor Green
    $shouldRun = $true
} else {
    $choiceIndex = Select-RobloxPath -paths $robloxPaths
    if ($choiceIndex -lt $robloxPaths.Count) {
        $selectedPath = $robloxPaths[$choiceIndex]
        Write-Host "[*] Selected: $selectedPath" -ForegroundColor Green
        $shouldRun = $true
    } else {
        Write-Host "[*] Roblox launch skipped." -ForegroundColor Yellow
    }
}

if ($shouldRun -and $null -ne $selectedPath) {
    $confirmRun = ""
    while ($confirmRun -notmatch "^[YN]$") {
        $confirmRun = Read-Host "Do you want to run it? (Y/N)"
        $confirmRun = $confirmRun.Trim().ToUpper()
    }
    if ($confirmRun -eq "Y") {
        Write-Host "[*] Launching RobloxPlayerBeta.exe..." -ForegroundColor Yellow
        try {
            Start-Process -FilePath $selectedPath
            Write-Host "[+] Roblox process started." -ForegroundColor Green
        } catch {
            Write-Host "[!] Failed to launch Roblox: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "[*] Roblox launch skipped." -ForegroundColor Yellow
    }
}
Write-Host ""

# Ask to run injector.exe (runs inside this console window)
$injectorPath = Join-Path $binDir "injector.exe"
if (Test-Path $injectorPath) {
    $runInjector = ""
    while ($runInjector -notmatch "^[YN]$") {
        $runInjector = Read-Host "Do you want to run injector.exe? (Y/N)"
        $runInjector = $runInjector.Trim().ToUpper()
    }
    
    if ($runInjector -eq "Y") {
        Write-Host "[*] Launching injector.exe in the current console..." -ForegroundColor Yellow
        try {
            # Change directory to the bin directory so it runs relative to its DLLs
            Set-Location -Path $binDir
            [System.IO.Directory]::SetCurrentDirectory($binDir)
            
            # Execute inline
            & .\injector.exe
        } catch {
            Write-Host "[!] Failed to launch injector.exe: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "[*] injector.exe execution skipped." -ForegroundColor Yellow
    }
} else {
    Write-Host "[!] injector.exe was not found in the bin directory." -ForegroundColor Red
}
Write-Host ""

# Keystroke verification before console exit
Write-Host "Process completed. Press any key to exit..." -ForegroundColor Cyan
try {
    $null = [System.Console]::ReadKey($true)
} catch {
    $null = Read-Host
}
Write-Host "Exited."
