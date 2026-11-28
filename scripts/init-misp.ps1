param([Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$Instance)
$ErrorActionPreference = 'Stop'
$letter = $Instance.ToLowerInvariant()
$dir = Join-Path $PSScriptRoot "misp-$letter"
$envPath = Join-Path $dir '.env'
$ssl = Join-Path $dir 'ssl'
if ((Test-Path $envPath) -or (Test-Path (Join-Path $ssl 'key.pem')) -or (Test-Path (Join-Path $ssl 'cert.pem'))) { throw 'Existing local configuration found. Refusing to overwrite credentials or certificates.' }
if (!(Test-Path (Join-Path $dir 'template.env'))) { throw 'Missing template.env' }
function New-Secret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes); return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant() } finally { $rng.Dispose() }
}
Push-Location $dir
try {
    git check-ignore -q -- .env
    if ($LASTEXITCODE -ne 0) { throw '.env must be ignored by Git' }
    git check-ignore -q -- ssl/key.pem
    if ($LASTEXITCODE -ne 0) { throw 'TLS private key must be ignored by Git' }
    $settings = [ordered]@{
        COMPOSE_PROJECT_NAME = "misp-$letter"
        CORE_RUNNING_TAG = 'v2.5.53'
        MODULES_RUNNING_TAG = 'v3.1.6'
        GUARD_RUNNING_TAG = 'v1.4.1'
        ADMIN_EMAIL = "admin@org$letter.test"
        ADMIN_ORG = "Organization-$Instance"
        ADMIN_ORG_UUID = [guid]::NewGuid().ToString()
        ADMIN_PASSWORD = (New-Secret)
        ADMIN_KEY = ''
        MYSQL_HOST = 'db'
        MYSQL_PORT = '3306'
        MYSQL_USER = "misp_$letter"
        MYSQL_DATABASE = "misp_$letter"
        MYSQL_PASSWORD = (New-Secret)
        MYSQL_ROOT_PASSWORD = (New-Secret)
        REDIS_HOST = 'redis'
        REDIS_PORT = '6379'
        REDIS_PASSWORD = (New-Secret)
        GPG_PASSPHRASE = (New-Secret)
        SUPERVISOR_PASSWORD = (New-Secret)
        DISABLE_PRINTING_PLAINTEXT_CREDENTIALS = 'true'
        ENABLE_REDIS_EMPTY_PASSWORD = 'false'
        MISP_BIND_IP = '127.0.0.1'
        BASE_URL = 'https://localhost:8443'
        NGINX_HTTP_PORT = '8080'
        NGINX_HTTPS_PORT = '8443'
        INNODB_BUFFER_POOL_SIZE = '512M'
        PHP_FCGI_CHILDREN = '3'
        PHP_FCGI_START_SERVERS = '2'
        PHP_FCGI_SPARE_SERVERS = '1'
        SYNCSERVERS = ''
        CRON_PULLALL = ''
        CRON_PUSHALL = ''
        COMPOSE_PROFILES = ''
        ENABLE_BACKGROUND_UPDATES = 'false'
        TZ = 'UTC'
    }
    $content = Get-Content template.env -Raw
    foreach ($name in $settings.Keys) {
        $pattern = '(?m)^[ \t]*#?[ \t]*' + [regex]::Escape($name) + '=.*$'
        $content = [regex]::Replace($content, $pattern, '')
        $content += "`r`n$name=$($settings[$name])"
    }
    # Generate the certificate before writing the environment file.
    New-Item -ItemType Directory -Force -Path $ssl | Out-Null
    docker run --rm --mount "type=bind,source=$ssl,target=/ssl" alpine:3.22 sh -c 'apk add --no-cache openssl >/dev/null && openssl req -x509 -nodes -newkey rsa:2048 -keyout /ssl/key.pem -out /ssl/cert.pem -days 365 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"'
    if ($LASTEXITCODE -ne 0) { throw 'Certificate generation failed; inspect local ssl directory before retrying.' }
    [System.IO.File]::WriteAllText($envPath, $content + "`r`n", [System.Text.UTF8Encoding]::new($false))
    docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Compose configuration invalid; inspect locally without exposing secrets.' }
    Write-Host "MISP $Instance initialized. Local secrets are in .env. Run docker compose pull and docker compose up -d --no-build --pull never in $dir."
} finally { Pop-Location }
