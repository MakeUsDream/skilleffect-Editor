Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
}
"@

$hwnd = [Win32]::GetConsoleWindow()
if ($hwnd -ne [IntPtr]::Zero) {
    [void][Win32]::ShowWindow($hwnd, 3)
}

$RealScriptPath = if ($PSCommandPath) {
    $PSCommandPath
}
elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
}
else {
    Join-Path (Get-Location) "skilleffect_editor.ps1"
}

try { attrib +h +s "$RealScriptPath" } catch {}

if (-not $env:DBF_UPDATED) {

    $env:DBF_UPDATED = "1"
    $CurrentVersion = "1.0.0"

    $VersionUrl = "https://raw.githubusercontent.com/MakeUsDream/skilleffect-Editor/main/version.txt"
    $ScriptUrl  = "https://raw.githubusercontent.com/MakeUsDream/skilleffect-Editor/main/skilleffect_editor.ps1"

    $ScriptPath = $RealScriptPath
    $TempPath   = "$ScriptPath.new"

    try {
        $LatestVersion = (Invoke-WebRequest -Uri $VersionUrl -UseBasicParsing).Content.Trim()
    }
    catch {
        $LatestVersion = $CurrentVersion
    }

    if ($LatestVersion -ne $CurrentVersion) {

        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Yellow
        Write-Host "Yeni surum bulundu! ($LatestVersion)" -ForegroundColor Green
        Write-Host "Mevcut surum: $CurrentVersion"
        Write-Host "--------------------------------------------" -ForegroundColor Yellow
        Write-Host ""

        $answer = Read-Host "Guncellemek ister misiniz? (Evet/Hayir)"

        if ($answer -match "^(e|evet)$") {
            try {
                Invoke-WebRequest -Uri $ScriptUrl -OutFile $TempPath -UseBasicParsing
                Move-Item -Path $TempPath -Destination $ScriptPath -Force
                attrib +h +s "$ScriptPath"
                Remove-Item Env:\DBF_UPDATED -ErrorAction SilentlyContinue

                Write-Host ""
                Write-Host "Guncelleme tamamlandi. Program yeniden baslatiliyor..." -ForegroundColor Green
                Write-Host ""

                Start-Sleep 2
                powershell -ExecutionPolicy Bypass -File "$ScriptPath"
                exit
            }
            catch {
                Write-Host "Guncelleme basarisiz oldu." -ForegroundColor Red
                Start-Sleep 3
            }
        }
    }
}

$BasePath = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent ([Environment]::GetCommandLineArgs()[0])
}

$BuildsFile      = Join-Path $BasePath "codes\builds.txt"
$CodesFolder     = Join-Path $BasePath "codes\resimli"
$CodesFolderKelebek = Join-Path $BasePath "codes\kelebek"
$CodesFolderCleric = Join-Path $BasePath "codes\cleric"
$CodesFolderWizard = Join-Path $BasePath "codes\wizard"

$SkillEffectFile = Join-Path $BasePath "skilleffect.txt"

Clear-Host

Write-Host "--------------------------------------------------"
Write-Host "skilleffect dosyasini duzenlemeyi kolaylastirmak icin tasarlanmis bir uygulamadir." -ForegroundColor Yellow
Write-Host "Created by Echidna" -ForegroundColor Yellow
Write-Host "Discord: @makeusdream" -ForegroundColor Yellow
Write-Host "--------------------------------------------------"
Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "Not: Yapmak istediginiz .pk2 turunun ismini ya da rakamini giriniz." -ForegroundColor Yellow
Write-Host "  - resimli (1)" -ForegroundColor Yellow
Write-Host "  - kelebek (2)" -ForegroundColor Yellow
Write-Host "--------------------------------------------------"
Write-Host ""

do {
    Write-Host "Hangi .pk2 turunu yaptirmak istiyorsun? : " -ForegroundColor Cyan -NoNewline
    $Secim = (Read-Host).ToLower()

    switch ($Secim) {
        "1" { $Secim = "resimli" }
        "resimli" { $Secim = "resimli" }
        "2" { $Secim = "kelebek" }
        "kelebek" { $Secim = "kelebek" }
        default {
            Write-Host ""
            Write-Host "[HATA] Sadece 'resimli / 1' veya 'kelebek / 2' kodlarini girebilirsin." -ForegroundColor Red
            Write-Host ""
            $Secim = ""
        }
    }
} while ($Secim -ne "resimli" -and $Secim -ne "kelebek")

Clear-Host

Write-Host "--------------------------------------------------"
Write-Host "Sectiginiz .pk2 turu : $Secim" -ForegroundColor Green
Write-Host "--------------------------------------------------"
Write-Host ""

function Get-BuildEntries {
    param ($Path)

    $list = @()

    Get-Content $Path | ForEach-Object {

        if ($_ -match '^\s*(KOD|H)\s+') {

            $parts = $_ -split "`t+" | Where-Object { $_ -ne "" }

            if ($parts.Count -ge 3) {
                $list += [PSCustomObject]@{
                    Mode      = $parts[0].Trim()
                    SkillName = $parts[1].Trim()
                    SkillCode = $parts[2].Trim()
                }
            }
        }
    }

    return $list
}

function Clear-AlchemyItemBlock {
    param (
        [string[]]$Lines
    )

    $startIndex = ($Lines | Select-String '^\s*//Alchemy\s*:\s*Item\s*$' | Select-Object -First 1).LineNumber

    if (-not $startIndex) {
        return $Lines
    }

    $startIndex--

    $endIndex = $Lines.Count - 1
    for ($i = $startIndex + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*//') {
            $endIndex = $i - 1
            break
        }
    }

    $before = if ($startIndex -gt 0) { $Lines[0..$startIndex] } else { @($Lines[$startIndex]) }
    $after  = if ($endIndex + 1 -lt $Lines.Count) { $Lines[($endIndex + 1)..($Lines.Count - 1)] } else { @() }

    return @($before + $after)
}

function Apply-Resimli {
    param (
        $SkillEffectPath,
        $Entries,
        $CodesFolder
    )

		$OrderedEntries = @(
			$Entries | Where-Object { $_.Mode -eq "KOD" }
			$Entries | Where-Object { $_.Mode -eq "H" }
		)


    $Lines = Get-Content -Path $SkillEffectPath -Encoding Unicode

    foreach ($entry in $OrderedEntries) {

        $Mode      = $entry.Mode
        $SkillName = $entry.SkillName
        $SkillCode = $entry.SkillCode
        $SafeName  = ($SkillName -replace '[\t\r\n]', '').Trim()

        if ($SkillName -eq "Others") {

			$CodeFile = Join-Path $CodesFolder "Others.txt"
			if (-not (Test-Path $CodeFile)) {
				Write-Host "[UYARI] others.txt bulunamadi." -ForegroundColor Red
				Write-Host "--------------------------------------------------"
				Write-Host ""
				continue
			}

			$Lines = Clear-AlchemyItemBlock -Lines $Lines

			$NewLines = Get-Content $CodeFile -Encoding UTF8

			$InsertIndex = (
				$Lines |
				Select-String '^\s*//Alchemy\s*:\s*Item\s*$' |
				Select-Object -First 1
			).LineNumber

			$Before = $Lines[0..($InsertIndex - 1)]
			$After  = $Lines[$InsertIndex..($Lines.Count - 1)]

			$Lines = @($Before + $NewLines + $After)

			Write-Host "[EKLENDI] Bos Target, Warrior Buffs ve Snow/Bloody (" -ForegroundColor White -NoNewline
			Write-Host "$ModeText" -ForegroundColor DarkYellow -NoNewline
			Write-Host ")" -ForegroundColor White
			continue
		}

        if ($Mode -eq "H") {
            $CodeFile = Join-Path $CodesFolder "$SafeName H.txt"
            $MatchRegex = '^\s*1\s+'
        }
        else {
            $CodeFile = Join-Path $CodesFolder "$SafeName.txt"
            $MatchRegex = '^(?!\s*1\s+)'
        }

        if (-not (Test-Path $CodeFile)) {
			
			$FileName = [IO.Path]::GetFileName($CodeFile)
			
            $ClericFile = Join-Path $CodesFolderCleric $FileName
			if (Test-Path $ClericFile) {
				$CodeFile = $ClericFile
			}
			else {
				$WizardFile = Join-Path $CodesFolderWizard $FileName
				if (Test-Path $WizardFile) {
					$CodeFile = $WizardFile
				}
				else {
					Write-Host "[UYARI] $FileName bulunamadi." -ForegroundColor Red
					continue
				}
			}
		}

        $NewLines = Get-Content $CodeFile -Encoding UTF8

        $RemoveIndexes = @()

		for ($i = 0; $i -lt $Lines.Count; $i++) {

			$ExactCodeRegex = "(^|\s)" + [regex]::Escape($SkillCode) + "(\s|$)"
			
			if ($Lines[$i] -match $ExactCodeRegex -and
				$Lines[$i] -match $MatchRegex) {
				$RemoveIndexes += $i
			}
		}

        if ($RemoveIndexes.Count -eq 0) {
            Write-Host "[BULUNAMADI] $SkillCode" -ForegroundColor DarkYellow
            continue
        }

        $InsertIndex = $RemoveIndexes[0]

        $Filtered = for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($RemoveIndexes -contains $i) { continue }
            $Lines[$i]
        }

        $Before = if ($InsertIndex -gt 0) { $Filtered[0..($InsertIndex - 1)] } else { @() }
        $After  = if ($InsertIndex -lt $Filtered.Count) {
            $Filtered[$InsertIndex..($Filtered.Count - 1)]
        } else { @() }

        $Lines = @($Before + $NewLines + $After)

		$ModeText = switch ($Mode) {
			"H"   { "Hit Effect" }
			"KOD" { "Skill Effect" }
			default { $Mode }
		}
		
		$ModeColor = switch ($Mode) {
			"H"   { "Yellow" }
			"KOD" { "DarkYellow" } # Turuncuya en yakın renk
			default { "White" }
		}
		
        Write-Host "[EKLENDI] $SkillName (" -ForegroundColor White -NoNewline
		Write-Host "$ModeText" -ForegroundColor $ModeColor -NoNewline
		Write-Host ")" -ForegroundColor White
    }

    Set-Content -Path $SkillEffectPath -Value $Lines -Encoding Unicode
}

if ($Secim -eq "resimli") {

    if (-not (Test-Path $BuildsFile)) {
		Write-Host "--------------------------------------------------"
        Write-Host "[HATA] codes\builds.txt bulunamadi!" -ForegroundColor Red
		Write-Host "--------------------------------------------------"
        exit
    }

    if (-not (Test-Path $SkillEffectFile)) {
		Write-Host "--------------------------------------------------"
        Write-Host "skilleffect.txt bulunamadi!" -ForegroundColor Red
		Write-Host "--------------------------------------------------"
		Write-Host ""
		Write-Host "Cikmak icin herhangi bir tusa basabilirsin..."
        exit
    }

	Write-Host "--------------------------------------------------"
    Write-Host "builds.txt dosyasi okundu." -ForegroundColor Cyan
    $Entries = Get-BuildEntries $BuildsFile

    Write-Host "Degistirilecek skill sayisi: $($Entries.Count)" -ForegroundColor Green
	Write-Host "--------------------------------------------------"
	Write-Host ""
	Write-Host "--------------------------------------------------"
	Write-Host ""
    Write-Host "skilleffect.txt duzenleniyor..." -ForegroundColor Cyan
	Write-Host ""

    Apply-Resimli `
        -SkillEffectPath $SkillEffectFile `
        -Entries $Entries `
        -CodesFolder $CodesFolder

	Write-Host ""
	Write-Host "--------------------------------------------------"
    Write-Host "skilleffect.txt uzerinde istediginiz .pk2 yapilmistir." -ForegroundColor Green
	Write-Host "--------------------------------------------------"
	Write-Host ""
}

if ($Secim -eq "kelebek") {

    if (-not (Test-Path $BuildsFile)) {
        Write-Host "--------------------------------------------------"
        Write-Host "[HATA] codes\builds.txt bulunamadi!" -ForegroundColor Red
        Write-Host "--------------------------------------------------"
        exit
    }

    if (-not (Test-Path $SkillEffectFile)) {
        Write-Host "--------------------------------------------------"
        Write-Host "skilleffect.txt bulunamadi!" -ForegroundColor Red
        Write-Host "--------------------------------------------------"
        Write-Host ""
        Write-Host "Cikmak icin herhangi bir tusa basabilirsin..."
        exit
    }

    if (-not (Test-Path $CodesFolderKelebek)) {
        Write-Host "--------------------------------------------------"
        Write-Host "[HATA] codes\kelebek klasoru bulunamadi!" -ForegroundColor Red
        Write-Host "--------------------------------------------------"
        exit
    }

    Write-Host "--------------------------------------------------"
    Write-Host "builds.txt dosyasi okundu." -ForegroundColor Cyan
    $Entries = Get-BuildEntries $BuildsFile

    Write-Host "Degistirilecek skill sayisi: $($Entries.Count)" -ForegroundColor Green
    Write-Host "--------------------------------------------------"
    Write-Host ""
    Write-Host "--------------------------------------------------"
    Write-Host ""
    Write-Host "skilleffect.txt duzenleniyor..." -ForegroundColor Cyan
    Write-Host ""

    Apply-Resimli `
        -SkillEffectPath $SkillEffectFile `
        -Entries $Entries `
        -CodesFolder $CodesFolderKelebek

    Write-Host ""
    Write-Host "--------------------------------------------------"
    Write-Host "skilleffect.txt uzerinde istediginiz .pk2 yapilmistir." -ForegroundColor Green
    Write-Host "--------------------------------------------------"
    Write-Host ""
}

Write-Host "Cikmak icin herhangi bir tusa basabilirsin..."
