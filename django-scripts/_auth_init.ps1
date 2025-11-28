Write-Host ""
Write-Host "=== Django Google Auth Setup (UiTM) ===" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------
#  Detect project name from folder
# ------------------------------------------
$folderName = Split-Path -Leaf (Get-Location).Path

function Get-SafeProjectName {
    param(
        [string]$Name
    )

    $n = $Name.Trim().ToLowerInvariant()
    $n = $n -replace '[\s\-]+', '_'
    $n = $n -replace '[^a-z0-9_]', ''

    if ($n -notmatch '^[a-z_][a-z0-9_]*$') {
        $n = "project_$n"
    }

    if ([string]::IsNullOrWhiteSpace($n)) {
        $n = "project"
    }

    return $n
}

$projectName = Get-SafeProjectName $folderName

Write-Host "Folder name: $folderName" -ForegroundColor Cyan
Write-Host "Using Django project name: $projectName" -ForegroundColor Cyan

$created = @()
$skipped = @()

# Paths
$settingsPath = ".\${projectName}_project\settings.py"
$urlsPath = ".\${projectName}_project\urls.py"
$venvActivate = ".\.venv\Scripts\Activate.ps1"

if (-not (Test-Path ".\manage.py")) {
    Write-Host "ERROR: manage.py not found. Run this script in the Django project root." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $settingsPath)) {
    Write-Host "ERROR: Cannot find $projectName`_project/settings.py" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $urlsPath)) {
    Write-Host "ERROR: Cannot find $projectName`_project/urls.py" -ForegroundColor Red
    exit 1
}

# ------------------------------------------
#  Activate venv
# ------------------------------------------
if (Test-Path $venvActivate) {
    Write-Host ""
    Write-Host "Activating virtual environment (.venv)..." -ForegroundColor Yellow
    & $venvActivate
    Write-Host "Virtual environment activated." -ForegroundColor Green
    $created += ".venv activated"
}
else {
    Write-Host "WARNING: .venv not found. Using global python." -ForegroundColor Yellow
    $skipped += ".venv activation (not found)"
}

# ------------------------------------------
#  Ensure accounts app exists
# ------------------------------------------
if (Test-Path ".\accounts") {
    Write-Host ""
    Write-Host "Django app 'accounts' already exists. Skipping startapp." -ForegroundColor Yellow
    $skipped += "accounts app (already exists)"
}
else {
    Write-Host ""
    Write-Host "Creating Django app: accounts ..." -ForegroundColor Yellow
    python manage.py startapp accounts
    if (Test-Path ".\accounts") {
        Write-Host "App 'accounts' created." -ForegroundColor Green
        $created += "accounts app (created)"
    }
    else {
        Write-Host "ERROR: accounts app not created." -ForegroundColor Red
        exit 1
    }
}

# ------------------------------------------
#  Update INSTALLED_APPS (accounts + social_django)
# ------------------------------------------
Write-Host ""
Write-Host "Updating INSTALLED_APPS with 'accounts' and 'social_django'..." -ForegroundColor Yellow

$settingsLines = Get-Content $settingsPath

$hasAccounts = ($settingsLines -contains '    "accounts",') -or ($settingsLines -contains "    'accounts',")
$hasSocial = ($settingsLines -contains '    "social_django",') -or ($settingsLines -contains "    'social_django',")

$insertIndex = -1
for ($i = 0; $i -lt $settingsLines.Length; $i++) {
    if ($settingsLines[$i] -match "django\.contrib\.staticfiles") {
        $insertIndex = $i + 1
        break
    }
}

if ($insertIndex -eq -1) {
    Write-Host "WARNING: Could not find django.contrib.staticfiles line. Please add apps manually if needed." -ForegroundColor Yellow
    $skipped += "INSTALLED_APPS update (no insertion point)"
}
else {
    $before = $settingsLines[0..($insertIndex - 1)]
    $after = $settingsLines[$insertIndex..($settingsLines.Length - 1)]

    $middle = @()
    if (-not $hasAccounts) {
        $middle += '    "accounts",'
        $created += "accounts added to INSTALLED_APPS"
        Write-Host "Added 'accounts' to INSTALLED_APPS." -ForegroundColor Green
    }
    else {
        $skipped += "accounts already in INSTALLED_APPS"
    }

    if (-not $hasSocial) {
        $middle += '    "social_django",'
        $created += "social_django added to INSTALLED_APPS"
        Write-Host "Added 'social_django' to INSTALLED_APPS." -ForegroundColor Green
    }
    else {
        $skipped += "social_django already in INSTALLED_APPS"
    }

    if ($middle.Count -gt 0) {
        $settingsLines = $before + $middle + $after
        $settingsLines | Set-Content $settingsPath -Encoding utf8
    }
}

# ------------------------------------------
#  Make sure 'import os' exists (for env vars)
# ------------------------------------------
$settingsText = Get-Content $settingsPath -Raw
if ($settingsText -notmatch "import os") {
    if ($settingsText -match "from pathlib import Path") {
        $settingsText = $settingsText -replace "from pathlib import Path", "from pathlib import Path`r`nimport os"
    }
    else {
        $settingsText = "import os`r`n" + $settingsText
    }
    $settingsText | Set-Content $settingsPath -Encoding utf8
    $created += "import os added"
    Write-Host "Added 'import os' to settings.py." -ForegroundColor Green
}

# reload after possible change
$settingsText = Get-Content $settingsPath -Raw

# ------------------------------------------
#  AUTHENTICATION_BACKENDS & Google settings
# ------------------------------------------
Write-Host ""
Write-Host "Ensuring AUTHENTICATION_BACKENDS and Google auth settings..." -ForegroundColor Yellow

if ($settingsText -notmatch "AUTHENTICATION_BACKENDS") {
    $authBlock = @'
AUTHENTICATION_BACKENDS = [
    "social_core.backends.google.GoogleOAuth2",
    "django.contrib.auth.backends.ModelBackend",
]

LOGIN_URL = "login"
LOGIN_REDIRECT_URL = "home"
LOGOUT_REDIRECT_URL = "home"

SOCIAL_AUTH_GOOGLE_OAUTH2_KEY = os.environ.get("GOOGLE_CLIENT_ID", "")
SOCIAL_AUTH_GOOGLE_OAUTH2_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")

SOCIAL_AUTH_GOOGLE_OAUTH2_WHITELISTED_DOMAINS = [
    "uitm.edu.my",
    "student.uitm.edu.my",
]

'@
    $settingsText = $settingsText + "`r`n`r`n" + $authBlock
    $settingsText | Set-Content $settingsPath -Encoding utf8
    $created += "AUTHENTICATION_BACKENDS + Google settings"
    Write-Host "Appended AUTHENTICATION_BACKENDS + Google settings." -ForegroundColor Green
}
else {
    Write-Host "AUTHENTICATION_BACKENDS already exists. Not touching it." -ForegroundColor Yellow
    $skipped += "AUTHENTICATION_BACKENDS (already present)"
}

# reload again for next edits
$settingsText = Get-Content $settingsPath -Raw

# ------------------------------------------
#  Add social_django context processors
# ------------------------------------------
Write-Host ""
Write-Host "Updating TEMPLATES context_processors..." -ForegroundColor Yellow

if ($settingsText -notmatch "social_django.context_processors.backends") {
    $settingsText = $settingsText -replace '"django.contrib.messages.context_processors.messages",', '"django.contrib.messages.context_processors.messages",`r`n                "social_django.context_processors.backends",'
    $created += "social_django.backends context_processor"
    Write-Host "Added social_django.context_processors.backends." -ForegroundColor Green
}
else {
    $skipped += "social_django.backends context_processor (already present)"
}

if ($settingsText -notmatch "social_django.context_processors.login_redirect") {
    $settingsText = $settingsText -replace '"social_django.context_processors.backends",', '"social_django.context_processors.backends",`r`n                "social_django.context_processors.login_redirect",'
    $created += "social_django.login_redirect context_processor"
    Write-Host "Added social_django.context_processors.login_redirect." -ForegroundColor Green
}
else {
    $skipped += "social_django.login_redirect context_processor (already present)"
}

$settingsText | Set-Content $settingsPath -Encoding utf8

# ------------------------------------------
#  Update project urls.py (auth/ + accounts/)
# ------------------------------------------
Write-Host ""
Write-Host "Updating project urls.py..." -ForegroundColor Yellow

$urlsText = Get-Content $urlsPath -Raw

if ($urlsText -match "from django.urls import path" -and $urlsText -notmatch "from django.urls import path, include") {
    $urlsText = $urlsText -replace "from django.urls import path", "from django.urls import path, include"
    $created += "urls import include"
    Write-Host "Updated urls import to include 'include'." -ForegroundColor Green
}

if ($urlsText -notmatch "social_django.urls") {
    $urlsText = $urlsText -replace '    path\("admin/", admin.site.urls\),', '    path("admin/", admin.site.urls),' + "`r`n    path(""auth/"", include(""social_django.urls"", namespace=""social"")),"
    $created += "auth/ route added"
    Write-Host "Added auth/ route for social_django." -ForegroundColor Green
}
else {
    $skipped += "auth/ route already exists"
}

if ($urlsText -notmatch "accounts.urls") {
    $urlsText = $urlsText -replace '    path\("admin/", admin.site.urls\),', '    path("admin/", admin.site.urls),' + "`r`n    path(""accounts/"", include(""accounts.urls"")),"
    $created += "accounts/ route added"
    Write-Host "Added accounts/ route." -ForegroundColor Green
}
else {
    $skipped += "accounts/ route already exists"
}

$urlsText | Set-Content $urlsPath -Encoding utf8

# ------------------------------------------
#  accounts/urls.py
# ------------------------------------------
Write-Host ""
Write-Host "Ensuring accounts/urls.py exists..." -ForegroundColor Yellow

$accountsUrlsPath = ".\accounts\urls.py"

if (-not (Test-Path $accountsUrlsPath)) {
    $accountsUrls = @'
from django.urls import path
from . import views

urlpatterns = [
    path("login/", views.login_view, name="login"),
    path("logout/", views.logout_view, name="logout"),
]
'@
    $accountsUrls | Set-Content $accountsUrlsPath -Encoding utf8
    $created += "accounts/urls.py created"
    Write-Host "Created accounts/urls.py." -ForegroundColor Green
}
else {
    $skipped += "accounts/urls.py already exists"
    Write-Host "accounts/urls.py already exists. Skipping." -ForegroundColor Yellow
}

# ------------------------------------------
#  accounts/views.py
# ------------------------------------------
Write-Host ""
Write-Host "Ensuring accounts/views.py has login_view and logout_view..." -ForegroundColor Yellow

$accountsViewsPath = ".\accounts\views.py"

if (-not (Test-Path $accountsViewsPath)) {
    $viewsContent = @'
from django.shortcuts import render, redirect
from django.contrib.auth import logout


def login_view(request):
    return render(request, "accounts/login.html")


def logout_view(request):
    logout(request)
    return redirect("home")
'@
    $viewsContent | Set-Content $accountsViewsPath -Encoding utf8
    $created += "accounts/views.py created"
    Write-Host "Created accounts/views.py." -ForegroundColor Green
}
else {
    $viewsText = Get-Content $accountsViewsPath -Raw

    if ($viewsText -notmatch "from\s+django\.shortcuts\s+import\s+render") {
        $viewsText = "from django.shortcuts import render, redirect`r`nfrom django.contrib.auth import logout`r`n`r`n" + $viewsText
    }
    elseif ($viewsText -notmatch "redirect") {
        $viewsText = $viewsText -replace "from django.shortcuts import render", "from django.shortcuts import render, redirect"
        if ($viewsText -notmatch "from django.contrib.auth import logout") {
            $viewsText = "from django.contrib.auth import logout`r`n" + $viewsText
        }
    }

    if ($viewsText -notmatch "def\s+login_view") {
        $loginFunc = @'

def login_view(request):
    return render(request, "accounts/login.html")
'@
        $viewsText += $loginFunc
        $created += "login_view added"
        Write-Host "Added login_view to accounts/views.py." -ForegroundColor Green
    }

    if ($viewsText -notmatch "def\s+logout_view") {
        $logoutFunc = @'

def logout_view(request):
    logout(request)
    return redirect("home")
'@
        $viewsText += $logoutFunc
        $created += "logout_view added"
        Write-Host "Added logout_view to accounts/views.py." -ForegroundColor Green
    }

    $viewsText | Set-Content $accountsViewsPath -Encoding utf8
}

# ------------------------------------------
#  accounts/templates/accounts/login.html
# ------------------------------------------
Write-Host ""
Write-Host "Ensuring login template exists..." -ForegroundColor Yellow

$accountsTemplatesDir = ".\accounts\templates\accounts"
if (-not (Test-Path $accountsTemplatesDir)) {
    New-Item -ItemType Directory -Path $accountsTemplatesDir -Force | Out-Null
}

$loginTemplatePath = Join-Path $accountsTemplatesDir "login.html"

if (-not (Test-Path $loginTemplatePath)) {
    $loginHtml = @'
{% extends "website/base.html" %}

{% block title %}Login | Website{% endblock %}

{% block content %}
<div class="d-flex justify-content-center my-5">
  <div class="card p-4" style="max-width: 400px; width: 100%;">
    <h3 class="mb-3 text-center">Sign in with UiTM Google</h3>
    <p class="text-muted text-center">
      Please use your official UiTM Google account.
    </p>

    <a href="{% url 'social:begin' 'google-oauth2' %}" class="btn btn-primary w-100">
      Continue with Google
    </a>
  </div>
</div>
{% endblock %}
'@
    $loginHtml | Set-Content $loginTemplatePath -Encoding utf8
    $created += "accounts/login.html created"
    Write-Host "Created accounts/login.html." -ForegroundColor Green
}
else {
    $skipped += "accounts/login.html already exists"
    Write-Host "accounts/login.html already exists. Skipping." -ForegroundColor Yellow
}

# ------------------------------------------
#  Update navbar nav.html
# ------------------------------------------
Write-Host ""
Write-Host "Updating navbar (website/templates/website/nav.html)..." -ForegroundColor Yellow

$navPath = ".\website\templates\website\nav.html"

if (Test-Path $navPath) {
    $navText = Get-Content $navPath -Raw

    if ($navText -match "{% url 'login' %}" -or $navText -match "{% url 'logout' %}") {
        $skipped += "navbar login/logout already present"
        Write-Host "Navbar already has login/logout links. Skipping." -ForegroundColor Yellow
    }
    else {
        $loginBlock = @'
        {% if user.is_authenticated %}
          <li class="nav-item">
            <a class="nav-link" href="{% url 'logout' %}">
              Logout ({{ user.email }})
            </a>
          </li>
        {% else %}
          <li class="nav-item">
            <a class="nav-link" href="{% url 'login' %}">
              Login
            </a>
          </li>
        {% endif %}
'@
        if ($navText -match "<!-- AUTO-GENERATED NAV END -->") {
            $navText = $navText -replace "        <!-- AUTO-GENERATED NAV END -->", "        <!-- AUTO-GENERATED NAV END -->`r`n$loginBlock"
        }
        else {
            $navText = $navText -replace "</ul>", "$loginBlock`r`n      </ul>"
        }

        $navText | Set-Content $navPath -Encoding utf8
        $created += "navbar login/logout links added"
        Write-Host "Navbar updated with login/logout links." -ForegroundColor Green
    }
}
else {
    $skipped += "nav.html not found"
    Write-Host "WARNING: nav.html not found, skipping navbar update." -ForegroundColor Yellow
}

# ------------------------------------------
#  Run migrations
# ------------------------------------------
Write-Host ""
Write-Host "Running python manage.py migrate..." -ForegroundColor Yellow
try {
    python manage.py migrate
    $created += "migrations run"
    Write-Host "Migrations completed." -ForegroundColor Green
}
catch {
    $skipped += "migrate failed"
    Write-Host "WARNING: migrate failed: $($_.Exception.Message)" -ForegroundColor Red
}

# ------------------------------------------
#  Summary
# ------------------------------------------
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan

Write-Host "  Created/Modified:" -ForegroundColor Green
if ($created.Count -eq 0) {
    Write-Host "   - (nothing new)" -ForegroundColor DarkGreen
}
else {
    $created | ForEach-Object { Write-Host "   - $_" -ForegroundColor Green }
}

Write-Host "  Skipped:" -ForegroundColor Yellow
if ($skipped.Count -eq 0) {
    Write-Host "   - (nothing skipped)" -ForegroundColor DarkYellow
}
else {
    $skipped | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "=== Google login setup finished ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Before running the server, set these env vars in PowerShell:" -ForegroundColor Cyan
Write-Host '  $env:GOOGLE_CLIENT_ID = "your_client_id_here"' -ForegroundColor Green
Write-Host '  $env:GOOGLE_CLIENT_SECRET = "your_client_secret_here"' -ForegroundColor Green
Write-Host ""
Write-Host "Then run: python manage.py runserver" -ForegroundColor Cyan
Write-Host ""
Write-Host "Remember to create OAuth 2.0 credentials in Google Cloud Console with UiTM domains whitelisted." -ForegroundColor Cyan
Write-Host ""
