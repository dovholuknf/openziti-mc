# Controller-side setup for ziti-minecraft.
#
# Prompts for controller URL + admin credentials, logs in, then provisions:
#   - server-mc and client-mc identities (tagged with role attributes)
#   - openziti-mc service
#   - Dial / Bind service policies matched by attribute
#   - Edge-router policies for #public routers
#   - Enrolled .json identity files in the current directory
#
# Prereqs:
#   - The `ziti` CLI on PATH
#   - At least one edge router registered with the `public` role attribute
#
# Run:    .\setup-ziti.ps1
# Bypass execution policy if needed:
#         powershell -ExecutionPolicy Bypass -File .\setup-ziti.ps1

$ErrorActionPreference = 'Stop'

# --- Inputs --------------------------------------------------------------

$controller = Read-Host -Prompt "Controller URL (e.g. https://sg4:1280 or sg4:1280)"
$adminUser  = Read-Host -Prompt "Admin username [admin]"
if ([string]::IsNullOrWhiteSpace($adminUser)) { $adminUser = 'admin' }
$adminPwdSecure = Read-Host -Prompt "Admin password" -AsSecureString
$adminPwd = [System.Net.NetworkCredential]::new("", $adminPwdSecure).Password

Write-Host ""
Write-Host "Logging into $controller as $adminUser ..."
ziti edge login $controller -u $adminUser -p $adminPwd
Write-Host ""

# --- Identities ---------------------------------------------------------

# Tag each identity with a role attribute so policies match by attribute, not by name.
# Adding a second player later is then `ziti edge create identity ... --role-attributes minecraft-clients`
# with no policy edits.
ziti edge create identity server-mc --role-attributes minecraft-server -o server-mc.jwt
ziti edge create identity client-mc --role-attributes minecraft-clients -o client-mc.jwt

# --- Service ------------------------------------------------------------

# No configs needed -- the mod dials and binds by service name directly.
ziti edge create service openziti-mc

# --- Service policies ---------------------------------------------------

ziti edge create service-policy mc-bind Bind --service-roles '@openziti-mc' --identity-roles '#minecraft-server'
ziti edge create service-policy mc-dial Dial --service-roles '@openziti-mc' --identity-roles '#minecraft-clients'

# --- Edge-router access -------------------------------------------------

# Skip these if your controller already has wildcard policies for #all identities on
# #public routers (the `ziti edge quickstart` setup does).
ziti edge create edge-router-policy mc-erp --edge-router-roles '#public' --identity-roles '#minecraft-server,#minecraft-clients'
ziti edge create service-edge-router-policy mc-serp --service-roles '@openziti-mc' --edge-router-roles '#public'

# --- Enroll the JWTs ----------------------------------------------------

ziti edge enroll --jwt server-mc.jwt -o server-mc.json
ziti edge enroll --jwt client-mc.jwt -o client-mc.json

Write-Host ""
Write-Host "Done. Enrolled identities written to:"
Write-Host "  $(Resolve-Path .\server-mc.json)"
Write-Host "  $(Resolve-Path .\client-mc.json)"
Write-Host ""
Write-Host "Next:"
Write-Host "  1. Move server-mc.json -> <server-instance>\config\openziti\identity.json"
Write-Host "  2. Move client-mc.json -> <client-instance>\config\openziti\identity.json"
Write-Host "  3. On the server, set 'OpenZiti server enabled' on and 'Service name' to 'openziti-mc'"
Write-Host "     via Mods -> OpenZiti MC -> Configure in-game, or write to <server-instance>\config\openziti.json:"
Write-Host "       { ""identityPath"": ""config/openziti/identity.json"", ""serverEnabled"": true, ""serviceName"": ""openziti-mc"" }"
Write-Host "     The client side needs no flag -- dialing service names is always active."
Write-Host "  4. Launch MC. Multiplayer -> Add Server -> Server Address: openziti-mc -> Join."
