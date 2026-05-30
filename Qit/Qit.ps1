# Qit.ps1 - Quick Git Push GUI
# Run via Qit.vbs to avoid console window

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ─── Username Storage ─────────────────────────────────────────────────────────

$configFile = Join-Path $PSScriptRoot "Qit.config"

function Get-SavedUsername {
    if (Test-Path $configFile) {
        $u = (Get-Content $configFile -Raw).Trim()
        if ($u -ne "") { return $u }
    }
    return $null
}

function Save-Username($username) {
    Set-Content -Path $configFile -Value $username.Trim()
}

function Prompt-ForUsername {
    $dlg                 = New-Object System.Windows.Forms.Form
    $dlg.Text            = "Qit -- GitHub Username"
    $dlg.Size            = New-Object System.Drawing.Size(400, 160)
    $dlg.StartPosition   = "CenterScreen"
    $dlg.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $dlg.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $dlg.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false

    $lbl              = New-Object System.Windows.Forms.Label
    $lbl.Text         = "Enter your GitHub username:"
    $lbl.Location     = New-Object System.Drawing.Point(16, 20)
    $lbl.AutoSize     = $true
    $lbl.ForeColor    = [System.Drawing.Color]::FromArgb(180, 180, 200)
    $dlg.Controls.Add($lbl)

    $txt              = New-Object System.Windows.Forms.TextBox
    $txt.Location     = New-Object System.Drawing.Point(16, 44)
    $txt.Size         = New-Object System.Drawing.Size(356, 24)
    $txt.BackColor    = [System.Drawing.Color]::FromArgb(30, 30, 42)
    $txt.ForeColor    = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $txt.BorderStyle  = "FixedSingle"
    $dlg.Controls.Add($txt)

    $btn              = New-Object System.Windows.Forms.Button
    $btn.Text         = "Save and Continue"
    $btn.Location     = New-Object System.Drawing.Point(16, 82)
    $btn.Size         = New-Object System.Drawing.Size(150, 32)
    $btn.BackColor    = [System.Drawing.Color]::FromArgb(35, 134, 54)
    $btn.ForeColor    = [System.Drawing.Color]::White
    $btn.FlatStyle    = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.AcceptButton = $btn
    $dlg.Controls.Add($btn)

    $txt.Select()
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $val = $txt.Text.Trim()
        if ($val -ne "") { return $val }
    }
    return $null
}

# ─── GitHub API Helper (public repos, no token needed) ───────────────────────

function Get-GitHubPublicRepos($username) {
    $repos = @()
    $page  = 1
    do {
        try {
            $uri      = "https://api.github.com/users/$username/repos?per_page=100&page=$page&sort=updated&type=owner"
            $headers  = @{ "User-Agent" = "Qit-App" }
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            if ($response.Count -eq 0) { break }
            $repos   += $response
            $page++
        } catch {
            return $null
        }
    } while ($response.Count -eq 100)
    return $repos
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Get-GitRemoteUrl {
    try {
        $url = git remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and $url) { return $url.Trim() }
    } catch {}
    return $null
}

function Is-GitRepo {
    try {
        git rev-parse --is-inside-work-tree 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    } catch { return $false }
}

function Get-GitBranch {
    try {
        $branch = git symbolic-ref --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { return $branch.Trim() }
    } catch {}
    return "unknown"
}

function Append-Log {
    param($textbox, $message, $color = [System.Drawing.Color]::FromArgb(220,220,220))
    $textbox.SelectionStart  = $textbox.TextLength
    $textbox.SelectionLength = 0
    $textbox.SelectionColor  = $color
    $textbox.AppendText("$message`n")
    $textbox.ScrollToCaret()
}

function Refresh-RepoInfo {
    $lblDir.Text   = (Get-Location).Path
    $isRepo2       = Is-GitRepo
    $branch2       = if ($isRepo2) { Get-GitBranch } else { "--" }
    $remote2       = Get-GitRemoteUrl

    if ($isRepo2 -and $remote2) {
        $lblRepo.Text        = "$remote2  [branch: $branch2]"
        $lblRepo.ForeColor   = [System.Drawing.Color]::FromArgb(88, 166, 255)
        $btnLinkRepo.Visible = $false
        $btnPush.Enabled     = $true
    } elseif ($isRepo2) {
        $lblRepo.Text        = "(local repo, no remote configured)"
        $lblRepo.ForeColor   = [System.Drawing.Color]::FromArgb(255, 200, 80)
        $btnLinkRepo.Visible = $true
        $btnPush.Enabled     = $false
    } else {
        $lblRepo.Text        = "Not linked -- click Link Repo to connect to GitHub"
        $lblRepo.ForeColor   = [System.Drawing.Color]::FromArgb(255, 100, 100)
        $btnLinkRepo.Visible = $true
        $btnPush.Enabled     = $false
    }
}

# ─── GitHub Connectivity Check ────────────────────────────────────────────────

$connected = $false
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $async     = $tcpClient.BeginConnect("github.com", 443, $null, $null)
    $waited    = $async.AsyncWaitHandle.WaitOne(3000, $false)
    if ($waited -and $tcpClient.Connected) { $connected = $true }
    $tcpClient.Close()
} catch {}

if (-not $connected) {
    [System.Windows.Forms.MessageBox]::Show(
        "Cannot reach GitHub (github.com:443).`n`nPlease check your internet connection or VPN and try again.",
        "Qit -- No Connection",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit
}

# ─── Git Installation Check ──────────────────────────────────────────────────

$gitFound = $false
try {
    $null = git --version 2>$null
    if ($LASTEXITCODE -eq 0) { $gitFound = $true }
} catch {}

if (-not $gitFound) {
    $install = [System.Windows.Forms.MessageBox]::Show(
        "Git is not installed on this machine.`n`nQit needs Git to work. Click Yes to install it now via winget (recommended), or No to open the Git download page in your browser.",
        "Qit -- Git Not Found",
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($install -eq [System.Windows.Forms.DialogResult]::Yes) {
        # Try winget install
        $wingetFound = $false
        try { $null = winget --version 2>$null; $wingetFound = ($LASTEXITCODE -eq 0) } catch {}

        if ($wingetFound) {
            [System.Windows.Forms.MessageBox]::Show(
                "Installing Git via winget...`n`nA terminal window will appear briefly. Qit will restart when done.",
                "Qit -- Installing Git",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            Start-Process "winget" -ArgumentList "install --id Git.Git -e --source winget" -Wait
            # Refresh PATH so git is available in this session
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            $null = git --version 2>$null
            if ($LASTEXITCODE -ne 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Git was installed but could not be found yet.`n`nPlease close and reopen Qit.",
                    "Qit -- Restart Required",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                exit
            }
        } else {
            # winget not available -- open download page
            Start-Process "https://git-scm.com/download/win"
            [System.Windows.Forms.MessageBox]::Show(
                "winget is not available on this machine.`n`nThe Git download page has been opened in your browser.`nInstall Git, then reopen Qit.",
                "Qit -- Install Git Manually",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            exit
        }
    } elseif ($install -eq [System.Windows.Forms.DialogResult]::No) {
        Start-Process "https://git-scm.com/download/win"
        [System.Windows.Forms.MessageBox]::Show(
            "The Git download page has been opened in your browser.`nInstall Git, then reopen Qit.",
            "Qit -- Install Git",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        exit
    } else {
        exit
    }
}

# ─── Git Identity Check ───────────────────────────────────────────────────────

$gitName  = git config --global user.name  2>$null
$gitEmail = git config --global user.email 2>$null

if ([string]::IsNullOrWhiteSpace($gitName) -or [string]::IsNullOrWhiteSpace($gitEmail)) {
    $idDlg                 = New-Object System.Windows.Forms.Form
    $idDlg.Text            = "Qit -- Git Identity Setup"
    $idDlg.Size            = New-Object System.Drawing.Size(400, 220)
    $idDlg.StartPosition   = "CenterScreen"
    $idDlg.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $idDlg.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $idDlg.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $idDlg.FormBorderStyle = "FixedDialog"
    $idDlg.MaximizeBox     = $false
    $idDlg.MinimizeBox     = $false

    $idLbl             = New-Object System.Windows.Forms.Label
    $idLbl.Text        = "Git needs your name and email for commits (one-time setup):"
    $idLbl.Location    = New-Object System.Drawing.Point(16, 16)
    $idLbl.Size        = New-Object System.Drawing.Size(360, 32)
    $idLbl.ForeColor   = [System.Drawing.Color]::FromArgb(180,180,200)
    $idDlg.Controls.Add($idLbl)

    $idLblName         = New-Object System.Windows.Forms.Label
    $idLblName.Text    = "Your name:"
    $idLblName.Location= New-Object System.Drawing.Point(16, 56)
    $idLblName.AutoSize= $true
    $idLblName.ForeColor=[System.Drawing.Color]::FromArgb(100,120,160)
    $idDlg.Controls.Add($idLblName)

    $idTxtName         = New-Object System.Windows.Forms.TextBox
    $idTxtName.Location= New-Object System.Drawing.Point(16, 74)
    $idTxtName.Size    = New-Object System.Drawing.Size(356, 24)
    $idTxtName.BackColor=[System.Drawing.Color]::FromArgb(30,30,42)
    $idTxtName.ForeColor=[System.Drawing.Color]::FromArgb(220,220,220)
    $idTxtName.BorderStyle="FixedSingle"
    $idTxtName.Text    = $gitName
    $idDlg.Controls.Add($idTxtName)

    $idLblEmail        = New-Object System.Windows.Forms.Label
    $idLblEmail.Text   = "Your email (same as GitHub):"
    $idLblEmail.Location=New-Object System.Drawing.Point(16, 106)
    $idLblEmail.AutoSize=$true
    $idLblEmail.ForeColor=[System.Drawing.Color]::FromArgb(100,120,160)
    $idDlg.Controls.Add($idLblEmail)

    $idTxtEmail        = New-Object System.Windows.Forms.TextBox
    $idTxtEmail.Location=New-Object System.Drawing.Point(16, 124)
    $idTxtEmail.Size   = New-Object System.Drawing.Size(356, 24)
    $idTxtEmail.BackColor=[System.Drawing.Color]::FromArgb(30,30,42)
    $idTxtEmail.ForeColor=[System.Drawing.Color]::FromArgb(220,220,220)
    $idTxtEmail.BorderStyle="FixedSingle"
    $idTxtEmail.Text   = $gitEmail
    $idDlg.Controls.Add($idTxtEmail)

    $idBtn             = New-Object System.Windows.Forms.Button
    $idBtn.Text        = "Save and Continue"
    $idBtn.Location    = New-Object System.Drawing.Point(16, 158)
    $idBtn.Size        = New-Object System.Drawing.Size(150, 32)
    $idBtn.BackColor   = [System.Drawing.Color]::FromArgb(35, 134, 54)
    $idBtn.ForeColor   = [System.Drawing.Color]::White
    $idBtn.FlatStyle   = "Flat"
    $idBtn.FlatAppearance.BorderSize = 0
    $idBtn.DialogResult= [System.Windows.Forms.DialogResult]::OK
    $idDlg.AcceptButton= $idBtn
    $idDlg.Controls.Add($idBtn)

    $idTxtName.Select()
    if ($idDlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $n = $idTxtName.Text.Trim()
        $e = $idTxtEmail.Text.Trim()
        if ($n -ne "") { git config --global user.name  $n }
        if ($e -ne "") { git config --global user.email $e }
    } else {
        exit
    }
}

# ─── Username Check ───────────────────────────────────────────────────────────

$githubUsername = Get-SavedUsername
if (-not $githubUsername) {
    $githubUsername = Prompt-ForUsername
    if (-not $githubUsername) { exit }
    Save-Username $githubUsername
}

# ─── Folder Picker ───────────────────────────────────────────────────────────

$folderBrowser                     = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description         = "Select your project folder"
$folderBrowser.ShowNewFolderButton = $false
$folderBrowser.RootFolder          = "MyComputer"
$folderBrowser.SelectedPath        = (Get-Location).Path

$result = $folderBrowser.ShowDialog()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit }
Set-Location $folderBrowser.SelectedPath

# ─── Main Form ───────────────────────────────────────────────────────────────

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "Qit"
$form.Size            = New-Object System.Drawing.Size(640, 620)
$form.StartPosition   = "CenterScreen"
$form.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)
$form.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 220)
$form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox     = $false

$accentPanel           = New-Object System.Windows.Forms.Panel
$accentPanel.Dock      = "Top"
$accentPanel.Height    = 4
$accentPanel.BackColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
$form.Controls.Add($accentPanel)

# Directory row
$lblDirTitle           = New-Object System.Windows.Forms.Label
$lblDirTitle.Text      = "DIRECTORY"
$lblDirTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
$lblDirTitle.ForeColor = [System.Drawing.Color]::FromArgb(100, 120, 160)
$lblDirTitle.Location  = New-Object System.Drawing.Point(16, 20)
$lblDirTitle.AutoSize  = $true
$form.Controls.Add($lblDirTitle)

$lblDir                = New-Object System.Windows.Forms.Label
$lblDir.Text           = (Get-Location).Path
$lblDir.Font           = New-Object System.Drawing.Font("Consolas", 9)
$lblDir.ForeColor      = [System.Drawing.Color]::FromArgb(220, 220, 220)
$lblDir.Location       = New-Object System.Drawing.Point(16, 38)
$lblDir.Size           = New-Object System.Drawing.Size(520, 18)
$lblDir.AutoEllipsis   = $true
$form.Controls.Add($lblDir)

$btnChangeFolder       = New-Object System.Windows.Forms.Button
$btnChangeFolder.Text  = "Change..."
$btnChangeFolder.Location = New-Object System.Drawing.Point(540, 33)
$btnChangeFolder.Size     = New-Object System.Drawing.Size(78, 24)
$btnChangeFolder.BackColor= [System.Drawing.Color]::FromArgb(40, 40, 58)
$btnChangeFolder.ForeColor= [System.Drawing.Color]::FromArgb(180, 180, 200)
$btnChangeFolder.FlatStyle= "Flat"
$btnChangeFolder.FlatAppearance.BorderSize  = 1
$btnChangeFolder.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 60, 80)
$btnChangeFolder.Font     = New-Object System.Drawing.Font("Segoe UI", 8)
$btnChangeFolder.Cursor   = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnChangeFolder)

# Repo row
$lblRepoTitle          = New-Object System.Windows.Forms.Label
$lblRepoTitle.Text     = "GITHUB REPO"
$lblRepoTitle.Font     = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
$lblRepoTitle.ForeColor= [System.Drawing.Color]::FromArgb(100, 120, 160)
$lblRepoTitle.Location = New-Object System.Drawing.Point(16, 66)
$lblRepoTitle.AutoSize = $true
$form.Controls.Add($lblRepoTitle)

$lblRepo               = New-Object System.Windows.Forms.Label
$lblRepo.Font          = New-Object System.Drawing.Font("Consolas", 9)
$lblRepo.Location      = New-Object System.Drawing.Point(16, 84)
$lblRepo.Size           = New-Object System.Drawing.Size(420, 18)
$lblRepo.AutoEllipsis  = $true
$form.Controls.Add($lblRepo)

$btnLinkRepo           = New-Object System.Windows.Forms.Button
$btnLinkRepo.Text      = "Link Repo..."
$btnLinkRepo.Location = New-Object System.Drawing.Point(468, 79)
$btnLinkRepo.Size           = New-Object System.Drawing.Size(148, 24)
$btnLinkRepo.BackColor = [System.Drawing.Color]::FromArgb(88, 60, 160)
$btnLinkRepo.ForeColor = [System.Drawing.Color]::White
$btnLinkRepo.FlatStyle = "Flat"
$btnLinkRepo.FlatAppearance.BorderSize = 0
$btnLinkRepo.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnLinkRepo.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnLinkRepo.Visible   = $false
$form.Controls.Add($btnLinkRepo)

# Divider
$divider               = New-Object System.Windows.Forms.Panel
$divider.Location      = New-Object System.Drawing.Point(16, 112)
$divider.Size            = New-Object System.Drawing.Size(600, 1)
$divider.BackColor     = [System.Drawing.Color]::FromArgb(45, 45, 60)
$form.Controls.Add($divider)

# Commit message
$lblMsgTitle           = New-Object System.Windows.Forms.Label
$lblMsgTitle.Text      = "COMMIT MESSAGE"
$lblMsgTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
$lblMsgTitle.ForeColor = [System.Drawing.Color]::FromArgb(100, 120, 160)
$lblMsgTitle.Location  = New-Object System.Drawing.Point(16, 124)
$lblMsgTitle.AutoSize  = $true
$form.Controls.Add($lblMsgTitle)

$txtMessage            = New-Object System.Windows.Forms.TextBox
$txtMessage.Location   = New-Object System.Drawing.Point(16, 142)
$txtMessage.Size           = New-Object System.Drawing.Size(600, 24)
$txtMessage.BackColor  = [System.Drawing.Color]::FromArgb(30, 30, 42)
$txtMessage.ForeColor  = [System.Drawing.Color]::FromArgb(220, 220, 220)
$txtMessage.BorderStyle= "FixedSingle"
$txtMessage.Font       = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($txtMessage)

# Output log
$lblLogTitle           = New-Object System.Windows.Forms.Label
$lblLogTitle.Text      = "OUTPUT"
$lblLogTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
$lblLogTitle.ForeColor = [System.Drawing.Color]::FromArgb(100, 120, 160)
$lblLogTitle.Location  = New-Object System.Drawing.Point(16, 185)
$lblLogTitle.AutoSize  = $true
$form.Controls.Add($lblLogTitle)

$rtbLog                = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location       = New-Object System.Drawing.Point(16, 203)
$rtbLog.Size          = New-Object System.Drawing.Size(600, 270)
$rtbLog.BackColor      = [System.Drawing.Color]::FromArgb(12, 12, 18)
$rtbLog.ForeColor      = [System.Drawing.Color]::FromArgb(180, 180, 180)
$rtbLog.Font           = New-Object System.Drawing.Font("Consolas", 8.5)
$rtbLog.BorderStyle    = "FixedSingle"
$rtbLog.ReadOnly       = $true
$rtbLog.ScrollBars     = "Vertical"
$form.Controls.Add($rtbLog)

# Bottom buttons
$btnPush               = New-Object System.Windows.Forms.Button
$btnPush.Text          = "Quick Push"
$btnPush.Location      = New-Object System.Drawing.Point(16, 545)
$btnPush.Size          = New-Object System.Drawing.Size(120, 34)
$btnPush.BackColor     = [System.Drawing.Color]::FromArgb(35, 134, 54)
$btnPush.ForeColor     = [System.Drawing.Color]::White
$btnPush.FlatStyle     = "Flat"
$btnPush.FlatAppearance.BorderSize = 0
$btnPush.Font          = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnPush.Cursor        = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnPush)

$btnClear              = New-Object System.Windows.Forms.Button
$btnClear.Text         = "Clear Log"
$btnClear.Location     = New-Object System.Drawing.Point(146, 545)
$btnClear.Size         = New-Object System.Drawing.Size(90, 34)
$btnClear.BackColor    = [System.Drawing.Color]::FromArgb(40, 40, 58)
$btnClear.ForeColor    = [System.Drawing.Color]::FromArgb(180, 180, 200)
$btnClear.FlatStyle    = "Flat"
$btnClear.FlatAppearance.BorderSize  = 1
$btnClear.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 60, 80)
$btnClear.Font         = New-Object System.Drawing.Font("Segoe UI", 9)
$btnClear.Cursor       = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnClear)

$btnResetUser          = New-Object System.Windows.Forms.Button
$btnResetUser.Text     = "Change User"
$btnResetUser.Location = New-Object System.Drawing.Point(246, 545)
$btnResetUser.Size     = New-Object System.Drawing.Size(90, 34)
$btnResetUser.BackColor= [System.Drawing.Color]::FromArgb(40, 40, 58)
$btnResetUser.ForeColor= [System.Drawing.Color]::FromArgb(130, 130, 150)
$btnResetUser.FlatStyle= "Flat"
$btnResetUser.FlatAppearance.BorderSize  = 1
$btnResetUser.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 60, 80)
$btnResetUser.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$btnResetUser.Cursor   = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnResetUser)

# Populate repo info now that all controls exist
Refresh-RepoInfo

# ─── Logic ───────────────────────────────────────────────────────────────────

$btnChangeFolder.Add_Click({
    $fb2                     = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb2.Description         = "Select a different project folder"
    $fb2.ShowNewFolderButton = $false
    $fb2.SelectedPath        = (Get-Location).Path
    if ($fb2.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-Location $fb2.SelectedPath
        Refresh-RepoInfo
        $rtbLog.Clear()
        Append-Log $rtbLog "Switched to: $($fb2.SelectedPath)" ([System.Drawing.Color]::FromArgb(100,120,160))
    }
})

$btnLinkRepo.Add_Click({
    $btnLinkRepo.Enabled = $false
    $btnLinkRepo.Text    = "Loading repos..."
    $form.Refresh()

    $repos = Get-GitHubPublicRepos $githubUsername

    $btnLinkRepo.Enabled = $true
    $btnLinkRepo.Text    = "Link Repo..."

    if ($null -eq $repos) {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not fetch repos for user: $githubUsername`n`nCheck the username is correct.",
            "Qit -- API Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }
    if ($repos.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No public repositories found for: $githubUsername",
            "Qit -- No Repos",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    # Repo picker dialog
    $picker                 = New-Object System.Windows.Forms.Form
    $picker.Text            = "Qit -- Select Repo  ($githubUsername)"
    $picker.Size            = New-Object System.Drawing.Size(500, 420)
    $picker.StartPosition   = "CenterScreen"
    $picker.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $picker.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $picker.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $picker.FormBorderStyle = "FixedDialog"
    $picker.MaximizeBox     = $false
    $picker.MinimizeBox     = $false

    $pLbl               = New-Object System.Windows.Forms.Label
    $pLbl.Text          = "Select the public repo to link  (type to filter):"
    $pLbl.Location      = New-Object System.Drawing.Point(16, 16)
    $pLbl.AutoSize      = $true
    $pLbl.ForeColor     = [System.Drawing.Color]::FromArgb(180,180,200)
    $picker.Controls.Add($pLbl)

    $pSearch            = New-Object System.Windows.Forms.TextBox
    $pSearch.Location   = New-Object System.Drawing.Point(16, 40)
    $pSearch.Size       = New-Object System.Drawing.Size(460, 24)
    $pSearch.BackColor  = [System.Drawing.Color]::FromArgb(30, 30, 42)
    $pSearch.ForeColor  = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $pSearch.BorderStyle= "FixedSingle"
    $picker.Controls.Add($pSearch)

    $pList              = New-Object System.Windows.Forms.ListBox
    $pList.Location     = New-Object System.Drawing.Point(16, 74)
    $pList.Size         = New-Object System.Drawing.Size(460, 230)
    $pList.BackColor    = [System.Drawing.Color]::FromArgb(24, 24, 34)
    $pList.ForeColor    = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $pList.BorderStyle  = "FixedSingle"
    $pList.Font         = New-Object System.Drawing.Font("Consolas", 9)
    $picker.Controls.Add($pList)

    $repoMap = @{}
    foreach ($r in ($repos | Sort-Object { $_.updated_at } -Descending)) {
        $pList.Items.Add($r.name) | Out-Null
        $repoMap[$r.name] = $r.clone_url
    }

    $pSearch.Add_TextChanged({
        $filter = $pSearch.Text.Trim().ToLower()
        $pList.Items.Clear()
        foreach ($r in ($repos | Sort-Object { $_.updated_at } -Descending)) {
            if ($r.name.ToLower().Contains($filter)) {
                $pList.Items.Add($r.name) | Out-Null
            }
        }
    })

    $pLblMsg            = New-Object System.Windows.Forms.Label
    $pLblMsg.Text       = "Initial commit message:"
    $pLblMsg.Location   = New-Object System.Drawing.Point(16, 315)
    $pLblMsg.AutoSize   = $true
    $pLblMsg.ForeColor  = [System.Drawing.Color]::FromArgb(100,120,160)
    $picker.Controls.Add($pLblMsg)

    $pTxtMsg            = New-Object System.Windows.Forms.TextBox
    $pTxtMsg.Location   = New-Object System.Drawing.Point(16, 334)
    $pTxtMsg.Size       = New-Object System.Drawing.Size(460, 24)
    $pTxtMsg.BackColor  = [System.Drawing.Color]::FromArgb(30, 30, 42)
    $pTxtMsg.ForeColor  = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $pTxtMsg.BorderStyle= "FixedSingle"
    $pTxtMsg.Text       = "Initial commit"
    $picker.Controls.Add($pTxtMsg)

    $pBtn               = New-Object System.Windows.Forms.Button
    $pBtn.Text          = "Link and Upload"
    $pBtn.Location      = New-Object System.Drawing.Point(16, 368)
    $pBtn.Size          = New-Object System.Drawing.Size(140, 32)
    $pBtn.BackColor     = [System.Drawing.Color]::FromArgb(88, 60, 160)
    $pBtn.ForeColor     = [System.Drawing.Color]::White
    $pBtn.FlatStyle     = "Flat"
    $pBtn.FlatAppearance.BorderSize = 0
    $pBtn.Font          = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $pBtn.DialogResult  = [System.Windows.Forms.DialogResult]::OK
    $picker.AcceptButton= $pBtn
    $picker.Controls.Add($pBtn)

    $pSearch.Select()
    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    if ($pList.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Please select a repo from the list.", "Qit", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $selectedName = $pList.SelectedItem.ToString()
    $repoUrl      = $repoMap[$selectedName]
    $commitMsg    = $pTxtMsg.Text.Trim()
    if ($commitMsg -eq "") { $commitMsg = "Initial commit" }

    Append-Log $rtbLog "------------------------------" ([System.Drawing.Color]::FromArgb(50,50,70))
    Append-Log $rtbLog "Linking to: $repoUrl"

    if (-not (Is-GitRepo)) {
        Append-Log $rtbLog ">> git init"
        $o = git init 2>&1
        if ($LASTEXITCODE -ne 0) {
            Append-Log $rtbLog "FAILED: git init: $o" ([System.Drawing.Color]::FromArgb(255,100,100))
            return
        }
        Append-Log $rtbLog "OK: Repository initialised" ([System.Drawing.Color]::FromArgb(80,200,120))
    }

    Append-Log $rtbLog ">> git remote add origin $repoUrl"
    $o = git remote add origin $repoUrl 2>&1
    if ($LASTEXITCODE -ne 0) {
        $o2 = git remote set-url origin $repoUrl 2>&1
        if ($LASTEXITCODE -ne 0) {
            Append-Log $rtbLog "FAILED: set remote: $o2" ([System.Drawing.Color]::FromArgb(255,100,100))
            return
        }
        Append-Log $rtbLog "OK: Remote updated" ([System.Drawing.Color]::FromArgb(80,200,120))
    } else {
        Append-Log $rtbLog "OK: Remote added" ([System.Drawing.Color]::FromArgb(80,200,120))
    }

    Append-Log $rtbLog ">> git add ."
    $o = git add . 2>&1
    if ($LASTEXITCODE -ne 0) {
        Append-Log $rtbLog "FAILED: git add: $o" ([System.Drawing.Color]::FromArgb(255,100,100))
        return
    }
    Append-Log $rtbLog "OK: All files staged" ([System.Drawing.Color]::FromArgb(80,200,120))

    Append-Log $rtbLog ">> git commit -m `"$commitMsg`""
    $o = git commit -m $commitMsg 2>&1
    if ($LASTEXITCODE -ne 0) {
        Append-Log $rtbLog "FAILED: git commit: $o" ([System.Drawing.Color]::FromArgb(255,100,100))
        return
    }
    Append-Log $rtbLog "OK: Committed" ([System.Drawing.Color]::FromArgb(80,200,120))

    Append-Log $rtbLog ">> git branch -M main"
    $o = git branch -M main 2>&1
    Append-Log $rtbLog "OK: Branch set to main" ([System.Drawing.Color]::FromArgb(80,200,120))

    Append-Log $rtbLog ">> git push -u origin main --force"
    $o = git push -u origin main --force 2>&1
    if ($LASTEXITCODE -ne 0) {
        Append-Log $rtbLog "FAILED: git push: $o" ([System.Drawing.Color]::FromArgb(255,100,100))
        return
    }
    Append-Log $rtbLog "SUCCESS: Folder linked and force-pushed to GitHub!" ([System.Drawing.Color]::FromArgb(88,166,255))

    Refresh-RepoInfo
})

$btnPush.Add_Click({
    $msg = $txtMessage.Text.Trim()
    if (-not (Is-GitRepo)) {
        Append-Log $rtbLog "ERROR: Not a git repository." ([System.Drawing.Color]::FromArgb(255,100,100))
        return
    }
    if ([string]::IsNullOrWhiteSpace($msg)) {
        Append-Log $rtbLog "ERROR: Please enter a commit message." ([System.Drawing.Color]::FromArgb(255,200,80))
        $txtMessage.Focus()
        return
    }

    $btnPush.Enabled = $false
    $btnPush.Text    = "Pushing..."
    $currentBranch   = Get-GitBranch

    Append-Log $rtbLog "------------------------------" ([System.Drawing.Color]::FromArgb(50,50,70))
    Append-Log $rtbLog ">> git add ."
    $o = git add . 2>&1
    if ($LASTEXITCODE -ne 0) {
        Append-Log $rtbLog "FAILED: git add: $o" ([System.Drawing.Color]::FromArgb(255,100,100))
        $btnPush.Enabled = $true; $btnPush.Text = "Quick Push"; return
    }
    Append-Log $rtbLog "OK: Staged all changes" ([System.Drawing.Color]::FromArgb(80,200,120))

    Append-Log $rtbLog ">> git commit -m `"$msg`""
    $o = git commit -m $msg 2>&1
    if ($LASTEXITCODE -ne 0) {
        Append-Log $rtbLog "FAILED: git commit: $o" ([System.Drawing.Color]::FromArgb(255,100,100))
        $btnPush.Enabled = $true; $btnPush.Text = "Quick Push"; return
    }
    Append-Log $rtbLog "OK: Committed: $msg" ([System.Drawing.Color]::FromArgb(80,200,120))

    Append-Log $rtbLog ">> git push"
    $o = git push 2>&1
    if ($LASTEXITCODE -ne 0) {
        Append-Log $rtbLog "FAILED: git push: $o" ([System.Drawing.Color]::FromArgb(255,100,100))
        $btnPush.Enabled = $true; $btnPush.Text = "Quick Push"; return
    }
    Append-Log $rtbLog "SUCCESS: Pushed to $currentBranch" ([System.Drawing.Color]::FromArgb(88,166,255))

    $txtMessage.Clear()
    $btnPush.Enabled = $true
    $btnPush.Text    = "Quick Push"
})

$btnClear.Add_Click({ $rtbLog.Clear() })

$btnResetUser.Add_Click({
    $newUser = Prompt-ForUsername
    if ($newUser) {
        Save-Username $newUser
        $githubUsername = $newUser
        Append-Log $rtbLog "Username updated to: $newUser" ([System.Drawing.Color]::FromArgb(100,120,160))
    }
})

$txtMessage.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $btnPush.PerformClick()
        $_.SuppressKeyPress = $true
    }
})

$form.Add_Shown({
    $form.Activate()
    $form.BringToFront()
    $form.TopMost = $true
    $form.TopMost = $false
})

$txtMessage.Select()
[System.Windows.Forms.Application]::Run($form)
