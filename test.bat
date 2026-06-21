<# :
@echo off
title NOTHING YUB-X TESTER
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0') -join [Environment]::NewLine)"
exit /b
#>

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "             NOTHING YUB-X SYSTEM TESTER          " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Determine target bin directory
$binDir = Join-Path $env:APPDATA "com.YUB-X.ui\YUB-X UI\bin"
Write-Host "[*] Checking files in bin directory: $binDir" -ForegroundColor Yellow

$yubxDllPath = Join-Path $binDir "yubx.dll"
$injectorPath = Join-Path $binDir "injector.exe"
$loaderPath = Join-Path $binDir "Loader.exe"

$missingRequired = $false

if (Test-Path $yubxDllPath) {
    Write-Host "[+] Found yubx.dll in bin." -ForegroundColor Green
} else {
    Write-Host "[!] Missing required file: yubx.dll" -ForegroundColor Red
    $missingRequired = $true
}

if (Test-Path $injectorPath) {
    Write-Host "[+] Found injector.exe in bin." -ForegroundColor Green
} else {
    Write-Host "[!] Missing required file: injector.exe" -ForegroundColor Red
    $missingRequired = $true
}

if (Test-Path $loaderPath) {
    Write-Host "[+] Found Loader.exe in bin." -ForegroundColor Green
} else {
    Write-Host "[-] Loader.exe was not found in bin (skipped)." -ForegroundColor Yellow
}
Write-Host ""

if ($missingRequired) {
    Write-Host "[!] Critical Error: Required files are missing from the bin directory. Please run the loader first." -ForegroundColor Red
    Write-Host "Press any key to exit..."
    try {
        $null = [System.Console]::ReadKey($true)
    } catch {
        $null = Read-Host
    }
    exit
}

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
