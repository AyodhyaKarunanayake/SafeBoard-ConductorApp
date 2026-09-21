<#
.SYNOPSIS
  Read-only check: did a passenger's "Text conductor" message reach Firebase, and would the
  conductor app show it?

.DESCRIPTION
  Lists the newest documents in `conductor_messages` (id, journey, bus, seat, status, time; the
  message text is shown, the passenger id is not) and the conductor's trips in `journey_instances`,
  then says whether each message matches a running trip. Nothing is written.

.EXAMPLE
  powershell -File tool\check_messages.ps1
#>
param([string]$ConductorId = 'CND_TEST')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$options = Get-Content (Join-Path $root 'lib\firebase_options.dart') -Raw
$apiKey = [regex]::Match($options, "apiKey:\s*'([^']+)'").Groups[1].Value
$projectId = [regex]::Match($options, "projectId:\s*'([^']+)'").Groups[1].Value
$restRoot = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents"
$headers = @{ 'x-goog-api-key' = $apiKey }

function Field($doc, $name) {
  $f = $doc.fields.$name
  if ($null -eq $f) { return '' }
  foreach ($k in 'stringValue', 'integerValue', 'booleanValue') { if ($null -ne $f.$k) { return "$($f.$k)" } }
  return ''
}

function Run-Query($collection, $field, $value) {
  $q = @{ structuredQuery = @{
      from  = @(@{ collectionId = $collection })
      where = @{ fieldFilter = @{ field = @{ fieldPath = $field }; op = 'EQUAL'; value = @{ stringValue = $value } } } } } | ConvertTo-Json -Depth 8
  $r = Invoke-RestMethod -Method Post -Uri "${restRoot}:runQuery" -Headers $headers -ContentType 'application/json' -Body $q
  return @($r | Where-Object { $_.document } | ForEach-Object { $_.document })
}

Write-Host "== Trips for conductor $ConductorId =="
$trips = Run-Query 'journey_instances' 'conductor_id' $ConductorId
if ($trips.Count -eq 0) { Write-Host '  (none)' }
foreach ($t in $trips) {
  Write-Host ("  journey={0}  bus={1}  status={2}" -f (Field $t 'journey_id'), (Field $t 'bus_id'), (Field $t 'status'))
}
$running = @($trips | Where-Object { (Field $_ 'status') -ne 'completed' })

Write-Host ''
Write-Host '== conductor_messages (all journeys) =='
try {
  $all = Invoke-RestMethod -Method Get -Uri "$restRoot/conductor_messages?pageSize=100" -Headers $headers
} catch {
  Write-Host "  Could not read the collection: $($_.Exception.Message)"
  return
}
$docs = @($all.documents)
if ($docs.Count -eq 0 -or $null -eq $docs[0]) {
  Write-Host '  NO MESSAGES EXIST. The passenger app never wrote one.'
  return
}
foreach ($d in ($docs | Sort-Object { Field $_ 'sent_datetime' } -Descending | Select-Object -First 10)) {
  $j = Field $d 'journey_id'; $b = Field $d 'bus_id'
  $match = $running | Where-Object { (Field $_ 'journey_id') -eq $j -and ((Field $_ 'bus_id') -eq $b -or $b -eq '') }
  $verdict = if ($match) { 'SHOWN in the conductor app' }
             elseif ($running | Where-Object { (Field $_ 'journey_id') -eq $j }) { "HIDDEN: same journey but a different bus (message bus=$b)" }
             else { "HIDDEN: the conductor is not running journey $j" }
  Write-Host ("  {0}  seat={1}  journey={2}  bus={3}  status={4}  text=""{5}""" -f (Field $d 'sent_datetime'), (Field $d 'seat_number'), $j, $b, (Field $d 'status'), (Field $d 'message_text'))
  Write-Host "      -> $verdict"
}
