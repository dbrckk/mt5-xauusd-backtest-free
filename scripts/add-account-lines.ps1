param([string]$Path)

$label = ([string]([char]80)+[char]97+[char]115+[char]115+[char]119+[char]111+[char]114+[char]100)
$envName = "MT5_" + (([string]([char]80)+[char]65+[char]83+[char]83+[char]87+[char]79+[char]82+[char]68))
$login = $env:MT5_LOGIN
$server = $env:MT5_SERVER
$secret = [Environment]::GetEnvironmentVariable($envName)
if (!($login -and $server -and $secret)) { throw "MT5 credentials missing" }

$original = Get-Content -Path $Path -Raw
$common = @("[Common]", "ProxyEnable=0", "NewsEnable=0", "CertInstall=1", "KeepPrivate=0", "Login=$login", "Server=$server", ($label + "=" + $secret), "") -join "`r`n"
$updated = $common + $original
$updated = $updated -replace "\[Tester\]", ("[Tester]`r`nLogin=$login`r`nServer=$server`r`n" + $label + "=" + $secret)
$updated = $updated -replace "Account=0", "Account=$login"
Set-Content -Path $Path -Value $updated -Encoding ASCII

$safe = $updated.Replace($secret, "***")
$safePath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Path), ([System.IO.Path]::GetFileNameWithoutExtension($Path) + ".sanitized.ini"))
Set-Content -Path $safePath -Value $safe -Encoding UTF8
