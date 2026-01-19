$RealScriptPath = if ($PSCommandPath) {
    $PSCommandPath
}
elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
}
else {
    Join-Path (Get-Location) "skilleffect_Editor.ps1"
}

try { attrib +h +s "$RealScriptPath" } catch {}

if (-not $env:DBF_UPDATED) {

    $env:DBF_UPDATED = "1"
    $CurrentVersion = "1.0.4"

    $VersionUrl = "https://raw.githubusercontent.com/MakeUsDream/skilleffect-Editor/main/version.txt"
    $ScriptUrl  = "https://raw.githubusercontent.com/MakeUsDream/skilleffect-Editor/main/skilleffect_Editor.ps1"

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
        Write-Host "Yeni surum bulundu! $LatestVersion" -ForegroundColor Green
        Write-Host "Mevcut surum: $CurrentVersion" -ForegroundColor DarkYellow
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

$BuildsFile      = Join-Path $BasePath "allcodes\builds.txt"
$SkillEffectFile = Join-Path $BasePath "skilleffect.txt"

Clear-Host

Write-Host "--------------------------------------------------"
Write-Host "  skilleffect dosyasini duzenlemeyi kolaylastirmak icin tasarlanmis bir uygulamadir." -ForegroundColor Yellow
Write-Host "  Created by Echidna" -ForegroundColor Yellow
Write-Host "  Discord: @makeusdream" -ForegroundColor Yellow
Write-Host "--------------------------------------------------"
Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "  Yapmak istediginiz .pk2 turunun ismini ya da temsili rakamini giriniz." -ForegroundColor Yellow
Write-Host ""
Write-Host " -resimli / 1  -> Echidna Resimli Media.pk2 (EU/CHN Marks + Wizard/Cleric Effect Off)" -ForegroundColor DarkYellow
Write-Host " -kelebek / 2  -> Podo Kelebek Media.pk2 (EU/CHN Marks + Wizard/Cleric Effect Off)" -ForegroundColor DarkYellow
Write-Host " -resimli100 / 3  -> Echidna Resimli Media.pk2 (CHN Marks for 100 cap + Heuksal/Pacheon/Cold/Light/Fire Effect Off)" -ForegroundColor DarkYellow
Write-Host " -medusa / 4  -> Medusa Petrify Media.pk2 (Wizard + Dagger + Heuksal + Fire Nuke's)" -ForegroundColor DarkYellow
Write-Host "--------------------------------------------------"
Write-Host ""

do {
    Write-Host "Hangi .pk2 turunu yaptirmak istiyorsun? : " -ForegroundColor Cyan -NoNewline
    $Secim = (Read-Host).ToLower()

    switch ($Secim) {
        "1" { $Secim = "resimli" }
        "resimli" { }

        "2" { $Secim = "kelebek" }
        "kelebek" { }

        "3" { $Secim = "resimli100" }
        "resimli100" { }
		
		"4" { $Secim = "medusa" }
		"medusa" { }

        default {
            Write-Host ""
            Write-Host "[HATA] Sadece 'resimli / 1', 'kelebek / 2', 'resimli100 / 3' veya 'medusa / 4' kodlarini girebilirsin." -ForegroundColor Red
            Write-Host ""
            $Secim = ""
        }
    }
} while ($Secim -notin @("resimli","kelebek","resimli100","medusa"))

Clear-Host

Write-Host ""
Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "  Istediginiz .pk2 yapiliyor. Biraz bekle..." -ForegroundColor Green
Write-Host "--------------------------------------------------"
Write-Host ""
Write-Host ""

$SelectedRoot = Join-Path $BasePath "allcodes\$Secim"
$CodesHE = Join-Path $SelectedRoot "he"
$CodesSE = Join-Path $SelectedRoot "se"

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
    param ([string[]]$Lines)

    $startMatch = $Lines | Select-String '^\s*//Alchemy\s*:\s*Item\s*$' | Select-Object -First 1
    if (-not $startMatch) { return $Lines }

    $startIndex = $startMatch.LineNumber - 1
    $endIndex = -1

    for ($i = $startIndex + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*//-\s*$') {
            $endIndex = $i
            break
        }
    }

    if ($endIndex -eq -1) { return $Lines }

    return @($Lines[0..$startIndex] + $Lines[($endIndex + 1)..($Lines.Count - 1)])
}

function Apply-Resimli {
    param (
        $SkillEffectPath,
        $Entries,
        $CodesHE,
        $CodesSE
    )

	$OthersEntry = $null

    $OrderedEntries = @(
        $Entries | Where-Object { $_.Mode -eq "KOD" }
        $Entries | Where-Object { $_.Mode -eq "H" }
    )

    $Lines = Get-Content -Path $SkillEffectPath -Encoding Unicode

    foreach ($entry in $OrderedEntries) {

        $Mode      = $entry.Mode
        $SkillName = $entry.SkillName
        $SkillCode = $entry.SkillCode
        $SafeName  = ($SkillName -replace "`t|`r|`n", '').Trim()

		if ($SkillName -eq "Others") {

			Write-Host "[EKLENDI] //Alchemy : Item (" -ForegroundColor White -NoNewline
			Write-Host "Skill Effect" -ForegroundColor DarkYellow -NoNewline
			Write-Host ")" -ForegroundColor White

			$OthersEntry = $entry
			continue
		}

        if ($Mode -eq "H") {
            $CodeFile = Join-Path $CodesHE "$SafeName.txt"
            $MatchRegex = '^\s*1\s+'
        }
        else {
            $CodeFile = Join-Path $CodesSE "$SafeName.txt"
            $MatchRegex = '^(?!\s*1\s+)'
        }

        if (-not (Test-Path $CodeFile)) {
			continue
        }

        $NewLines = Get-Content $CodeFile -Encoding UTF8
        $RemoveIndexes = @()

        for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i] -match [regex]::Escape($SkillCode) -and
                $Lines[$i] -match $MatchRegex) {
                $RemoveIndexes += $i
            }
        }

        if ($RemoveIndexes.Count -eq 0) { continue }

        $InsertIndex = $RemoveIndexes[0]

        $Filtered = for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($RemoveIndexes -contains $i) { continue }
            $Lines[$i]
        }

        $Lines = @(
            $Filtered[0..($InsertIndex - 1)] +
            $NewLines +
            $Filtered[$InsertIndex..($Filtered.Count - 1)]
        )

        $ModeText = switch ($Mode) {
			"H"   { "Hit Effect" }
			"KOD" { "Skill Effect" }
			default { $Mode }
		}

		$ModeColor = switch ($Mode) {
			"H"   { "Cyan" }
			"KOD" { "DarkYellow" }
			default { "White" }
		}

		Write-Host "[EKLENDI] $SkillName (" -ForegroundColor White -NoNewline
		Write-Host "$ModeText" -ForegroundColor $ModeColor -NoNewline
		Write-Host ")" -ForegroundColor White
		}

		if ($OthersEntry) {

			$CodeFile = Join-Path $CodesSE "Others.txt"
			if (Test-Path $CodeFile) {

				$Lines = Clear-AlchemyItemBlock -Lines $Lines
				$NewLines = Get-Content $CodeFile -Encoding UTF8

				$InsertIndex = (
					$Lines |
					Select-String '^\s*//Alchemy\s*:\s*Item\s*$' |
					Select-Object -First 1
			).LineNumber

			$Lines = @(
				$Lines[0..($InsertIndex - 1)] +
				$NewLines +
				$Lines[$InsertIndex..($Lines.Count - 1)]
			)
    }
}

    Set-Content -Path $SkillEffectPath -Value $Lines -Encoding Unicode
}

if (-not (Test-Path $BuildsFile)) {
	Write-Host ""
	Write-Host "--------------------------------------------------"
    Write-Host "[HATA] builds.txt bulunamadi!" -ForegroundColor Red
	Write-Host "--------------------------------------------------"
	Write-Host ""
	Write-Host "Cikmak icin herhangi bir tusa basabilirsin..."
    exit
}

if (-not (Test-Path $SkillEffectFile)) {
	Write-Host ""
	Write-Host "--------------------------------------------------"
    Write-Host "[HATA] skilleffect.txt bulunamadi!" -ForegroundColor Red
	Write-Host "--------------------------------------------------"
	Write-Host ""
	Write-Host "Cikmak icin herhangi bir tusa basabilirsin..."
    exit
}

$Entries = Get-BuildEntries $BuildsFile

Apply-Resimli `
    -SkillEffectPath $SkillEffectFile `
    -Entries $Entries `
    -CodesHE $CodesHE `
    -CodesSE $CodesSE

Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "skilleffect.txt uzerinde istediginiz .pk2 yapilmistir." -ForegroundColor Green
Write-Host "--------------------------------------------------"
Write-Host ""
Write-Host "Cikmak icin herhangi bir tusa basabilirsin..."




