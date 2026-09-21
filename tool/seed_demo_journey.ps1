<#
.SYNOPSIS
  Creates a demo trip (31 passengers, cash fares and incident reports) assigned to the test
  conductor, so every tab of the SafeBoard Conductor app has something to show.

.DESCRIPTION
  Default run (idempotent, safe to repeat):
    - journey_instances/<JourneyId>   an in-progress Route 87 trip assigned to the conductor
    - seat_allocations/demo_alloc_NN  31 passengers: 6 Priority, 9 General, 14 Limited, 2 Standing
    - payments/demo_pay_NN            5 cash fares waiting to be collected, 3 already collected,
                                      2 card payments (which the conductor app correctly ignores)
    - incident_reports/demo_inc_NN    3 incident reports (high / medium / resolved low)

  Live-demo switches (run them while the panel watches the app):
    -AddAllocation  a new passenger books a seat: the seat map, bars and list update, and an
                    alert appears. Add -WithCash to make that passenger pay on board too
                    (a "Cash to collect" alert and a new row on the Cash tab).
    -AddIncident    a passenger reports a high-severity incident (an alert and a new card).
    -AddSos         a passenger presses the SOS button, filed exactly as the passenger app files it
                    (status "escalated"): the conductor app pops up a full-screen SOS alert with
                    the seat number in big letters. Use -SosSeat to choose the seat (default 5C).
    -EndJourney     the passenger in -LeaveSeat (default 5D) ends their journey, marked 'released'
                    exactly as the passenger app now marks it: the seat empties on the seat map,
                    a 3-second "Seat 5D is empty" alert shows, and the conductor is asked whether
                    to give the seat to a standing passenger (the one travelling furthest first).
                    Re-run without switches afterwards to put the passenger back.
    -AddMessage     a passenger uses "Text conductor": a new message appears on the Messages page
                    with an unread badge and an alert. Use -MessageSeat / -MessageText to choose.

  Other switches:
    -NoSamples      only create/refresh the journey document.
    -Reset          delete everything this script created for -JourneyId.
    -Force          allow overwriting a journey document that belongs to another conductor.

  Data is written exactly as the passenger app writes it: snake_case field names and ISO-8601
  string dates. Every document id starts with "demo_" so it is easy to find and remove. It
  makes no login: it writes with the public API key from lib/firebase_options.dart, so it needs
  Firestore rules that allow those writes (they currently do). It also creates the
  conductors/<ConductorId> document if it is missing, so the demo conductor shows up in the
  app's login list; an existing conductor document is never modified.

.NOTES
  The default -JourneyId is JRN_DEMO_001, separate from the passenger app's own journey
  (JRN_87_001) so demo data cannot mix into your research data. The conductor app can also
  start a real trip itself on the Trip tab; use that to receive real passenger-app bookings.

.EXAMPLE
  powershell -File tool\seed_demo_journey.ps1
  powershell -File tool\seed_demo_journey.ps1 -AddAllocation -WithCash
  powershell -File tool\seed_demo_journey.ps1 -AddIncident
  powershell -File tool\seed_demo_journey.ps1 -Reset
#>
param(
  [string]$JourneyId = 'JRN_DEMO_001',
  [string]$ConductorId = 'CND_TEST',
  [string]$ConductorName = 'Test Conductor',
  [string]$BusId = 'BUS_NB_8710',
  [switch]$AddAllocation,
  [switch]$WithCash,
  [switch]$AddIncident,
  [switch]$AddSos,
  [string]$SosSeat = '5C',
  [switch]$EndJourney,
  [string]$LeaveSeat = '5D',
  [switch]$AddMessage,
  [string]$MessageSeat = '6A',
  [string]$MessageText = '',
  [switch]$NoSamples,
  [switch]$Reset,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ---- config from the app's own firebase_options.dart -------------------------------------
$root = Split-Path -Parent $PSScriptRoot
$options = Get-Content (Join-Path $root 'lib\firebase_options.dart') -Raw
$apiKey = [regex]::Match($options, "apiKey:\s*'([^']+)'").Groups[1].Value
$projectId = [regex]::Match($options, "projectId:\s*'([^']+)'").Groups[1].Value
if (-not $apiKey -or -not $projectId) { throw 'Could not read apiKey/projectId from firebase_options.dart' }

$docRoot = "projects/$projectId/databases/(default)/documents"
$restRoot = "https://firestore.googleapis.com/v1/$docRoot"

# ---- helpers -----------------------------------------------------------------------------
function Get-ErrorText($err) {
  if ($err.ErrorDetails -and $err.ErrorDetails.Message) { return $err.ErrorDetails.Message }
  $response = $err.Exception.Response
  if ($response) {
    try {
      $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
      $body = $reader.ReadToEnd()
      if ($body) { return $body }
    } catch { }
  }
  return $err.Exception.Message
}

# Firestore REST typed values. (int64 must be sent as a string.)
function Str([string]$v) { @{ stringValue = $v } }
function Int([long]$v) { @{ integerValue = "$v" } }
function Dbl([double]$v) { @{ doubleValue = $v } }
function Bool([bool]$v) { @{ booleanValue = $v } }
function NullVal() { @{ nullValue = $null } }

# Same format as JavaScript's toISOString(), which the passenger app's data uses.
function Iso([datetime]$utc) { $utc.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'") }
function MinutesAgo([int]$m) { Iso ((Get-Date).ToUniversalTime().AddMinutes(-$m)) }

function New-Write([string]$collection, [string]$id, $fields) {
  @{ update = @{ name = "$docRoot/$collection/$id"; fields = $fields } }
}
function New-Delete([string]$collection, [string]$id) {
  @{ delete = "$docRoot/$collection/$id" }
}

$script:headers = @{}

function Invoke-Commit($writes) {
  $body = @{ writes = @($writes) } | ConvertTo-Json -Depth 15
  try {
    Invoke-RestMethod -Method Post -Uri "${restRoot}:commit" -Headers $script:headers `
      -ContentType 'application/json' -Body $body | Out-Null
  } catch {
    throw "Firestore write failed (check your security rules allow authenticated writes): $(Get-ErrorText $_)"
  }
}

# Returns the document, or $null if it does not exist.
function Get-Doc([string]$collection, [string]$id) {
  try {
    return Invoke-RestMethod -Method Get -Uri "$restRoot/$collection/$id" -Headers $script:headers
  } catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }
    throw "Could not read ${collection}/${id}: $(Get-ErrorText $_)"
  }
}

# All documents of a collection whose journey_id is this journey (exact server-side query, so
# it is not affected by how many other documents the collection holds).
function Get-JourneyDocs([string]$collection) {
  $query = @{
    structuredQuery = @{
      from  = @(@{ collectionId = $collection })
      where = @{ fieldFilter = @{ field = @{ fieldPath = 'journey_id' }; op = 'EQUAL'; value = (Str $JourneyId) } }
    }
  } | ConvertTo-Json -Depth 10
  try {
    $result = Invoke-RestMethod -Method Post -Uri "${restRoot}:runQuery" -Headers $script:headers `
      -ContentType 'application/json' -Body $query
  } catch {
    return @()
  }
  return @($result | Where-Object { $_.document } | ForEach-Object { $_.document })
}

function Doc-Id($doc) { $doc.name.Split('/')[-1] }

# Requests go out with the public API key only (no login); see the notes above.
$script:headers = @{ 'x-goog-api-key' = $apiKey }

# ---- sample data --------------------------------------------------------------------------
# Stop names are the Route 87 (Colombo - Jaffna) stops as entered in the passenger app.
# The demo bus left Colombo (Pettah) $departedMinutesAgo minutes ago and is now at $currentStop,
# so every boarding stop is at or before it and every alighting stop is after it.
$departedMinutesAgo = 195
$currentStop = 'Puttalam Main Stand'
$fare = 1450.0

$seatPlan = @(
  @('priority', @('1A', '1B', '2A', '2C', '3D', '3E')),
  @('general', @('4A', '4B', '5C', '5D', '5E', '6A', '6B', '6D', '6E')),
  @('limited', @('7A', '7C', '8B', '8D', '9A', '9E', '10B', '10C', '11A', '11D', '12D', '13A', '13C', '13F')),
  @('standing', @('Standing-1', 'Standing-2'))
)
$alightings = @('Jaffna Main Bus Stand', 'Vavuniya Bus Terminal', 'Kilinochchi Central Stand', 'Anuradhapura New Town')

# Boarding stop and booking time by passenger number: earlier passengers boarded earlier.
function Get-Boarding([int]$i) {
  if ($i -lt 16) { return @('Colombo (Pettah)', (190 - $i)) }
  if ($i -lt 23) { return @('Negombo Bus Stand', (150 - 3 * ($i - 16))) }
  if ($i -lt 28) { return @('Chilaw Bus Stand', (90 - 5 * ($i - 23))) }
  return @('Puttalam Main Stand', (14 - 4 * ($i - 28)))
}

$samples = @()
$i = 0
foreach ($group in $seatPlan) {
  $zone = $group[0]
  $n = 0
  foreach ($seat in $group[1]) {
    $board = Get-Boarding $i
    $risk = switch ($zone) {
      'priority' { 0.05 }
      'general'  { if ($n % 4 -eq 0) { 0.25 } else { 0.10 } }
      'limited'  { if ($n % 3 -eq 0) { 0.35 } else { 0.20 } }
      'standing' { 0.50 + 0.06 * $n }
    }
    $samples += @{
      id = ('demo_alloc_{0:d2}' -f ($i + 1)); seat = $seat; zone = $zone; risk = $risk
      boarding = $board[0]; ago = $board[1]; alighting = $alightings[$i % 4]
      reserved = ($seat -eq '4B')   # a safety-preference passenger moved out of full Priority
    }
    $i++; $n++
  }
}
$sampleCount = $samples.Count

# seat -> payment plan. pending = pay on board, not yet collected.
$cashPending = @('5D', '7C', '9E', '6D', 'Standing-1')
$cashCollected = @('8B', '10B', '6A')
$cardPaid = @('1A', '2C', '4A', '11A')

# Extra passengers handed out one at a time by -AddAllocation.
$livePool = @(
  @('1C', 'priority', 0.05, 'Puttalam Main Stand', 'Jaffna Main Bus Stand'),
  @('4D', 'general', 0.10, 'Puttalam Main Stand', 'Vavuniya Bus Terminal'),
  @('7B', 'limited', 0.20, 'Anamaduwa', 'Jaffna Main Bus Stand'),
  @('2B', 'priority', 0.05, 'Anamaduwa', 'Kilinochchi Central Stand'),
  @('5A', 'general', 0.25, 'Puttalam Main Stand', 'Jaffna Main Bus Stand'),
  @('8A', 'limited', 0.35, 'Anamaduwa', 'Vavuniya Bus Terminal'),
  @('3A', 'priority', 0.05, 'Puttalam Main Stand', 'Jaffna Main Bus Stand'),
  @('6C', 'general', 0.10, 'Saliyawewa Junction', 'Anuradhapura New Town'),
  @('10E', 'limited', 0.20, 'Anamaduwa', 'Kilinochchi Central Stand'),
  @('11C', 'limited', 0.20, 'Saliyawewa Junction', 'Jaffna Main Bus Stand')
)

function New-AllocationFields($seat, $risk, $boarding, $alighting, [string]$allocId, [string]$bookingId, [string]$when, [bool]$reserved) {
  @{
    allocation_id       = (Str $allocId)
    booking_id          = (Str $bookingId)
    seat_id             = (Str $seat)
    seat_number         = (Str $seat)
    bus_id              = (Str $BusId)
    journey_id          = (Str $JourneyId)
    allocation_datetime = (Str $when)
    boarding_stop       = (Str $boarding)
    alighting_stop      = (Str $alighting)
    allocation_type     = (Str 'auto')
    risk_score          = (Dbl $risk)
    status              = (Str 'active')
    qr_code             = (Str "SB-$JourneyId-$seat-$allocId")
    priority_reserved   = (Bool $reserved)
  }
}

function New-PaymentFields([string]$payId, [string]$allocId, [string]$method, [string]$status, [string]$reference, [string]$when) {
  @{
    payment_id    = (Str $payId)
    allocation_id = (Str $allocId)
    journey_id    = (Str $JourneyId)
    method        = (Str $method)
    amount_lkr    = (Dbl $fare)
    status        = (Str $status)
    timestamp     = (Str $when)
    reference     = (Str $reference)
  }
}

# ---- -Reset -------------------------------------------------------------------------------
if ($Reset) {
  # The fixed sample ids are always deleted (deleting a missing document is harmless)...
  $ids = @{}
  1..$sampleCount | ForEach-Object { $ids[('seat_allocations/demo_alloc_{0:d2}' -f $_)] = $true }
  1..3 | ForEach-Object { $ids[('incident_reports/demo_inc_{0:d2}' -f $_)] = $true }
  1..12 | ForEach-Object { $ids[('payments/demo_pay_{0:d2}' -f $_)] = $true }
  1..3 | ForEach-Object { $ids[('conductor_messages/demo_msg_{0:d2}' -f $_)] = $true }
  # ...plus any live ones added with -AddAllocation / -AddIncident / -AddSos / -AddMessage.
  # Only "demo_" ids are touched.
  foreach ($collection in 'seat_allocations', 'incident_reports', 'payments', 'conductor_messages') {
    foreach ($doc in (Get-JourneyDocs $collection)) {
      $id = Doc-Id $doc
      if ($id -like 'demo_*') { $ids["$collection/$id"] = $true }
    }
  }
  $deletes = @()
  foreach ($path in ($ids.Keys | Sort-Object)) {
    $collection, $id = $path.Split('/')
    $deletes += (New-Delete $collection $id)
  }
  $journey = Get-Doc 'journey_instances' $JourneyId
  if ($journey -and $journey.fields.conductor_id.stringValue -eq $ConductorId) {
    $deletes += (New-Delete 'journey_instances' $JourneyId)
  } elseif ($journey) {
    Write-Host "Left journey_instances/$JourneyId in place: it belongs to another conductor."
  }
  Invoke-Commit $deletes
  Write-Host "Removed the demo documents for journey $JourneyId."
  return
}

# The passenger app's "Text conductor" presets.
$messagePresets = @(
  'Can I get a seat change?',
  'How many stops to my destination?',
  'The bus feels overcrowded right now',
  'Thank you, all good'
)

function New-MessageFields([string]$id, [string]$seat, [string]$text, [string]$status, [string]$when) {
  @{
    message_id    = (Str $id)
    journey_id    = (Str $JourneyId)
    bus_id        = (Str $BusId)
    passenger_id  = (Str 'demo_passenger')
    seat_number   = (Str $seat)
    message_text  = (Str $text)
    sent_datetime = (Str $when)
    status        = (Str $status)
  }
}

# ---- -EndJourney --------------------------------------------------------------------------
if ($EndJourney) {
  if (-not (Get-Doc 'journey_instances' $JourneyId)) {
    throw "Journey $JourneyId does not exist yet. Run this script once without -EndJourney first."
  }
  $target = Get-JourneyDocs 'seat_allocations' | Where-Object {
    $_.fields.seat_number.stringValue -eq $LeaveSeat -and
    $_.fields.status.stringValue -eq 'active' -and
    (Doc-Id $_) -like 'demo_*'
  } | Select-Object -First 1
  if (-not $target) {
    throw "No active demo passenger in seat $LeaveSeat. Run this script once without switches to reset, or pick another -LeaveSeat."
  }
  # What the passenger app does when a journey ends: mark the booking 'released'.
  # Only the status changes (updateMask), as in the passenger app.
  $id = Doc-Id $target
  Invoke-Commit @(@{
      update     = @{ name = "$docRoot/seat_allocations/$id"; fields = @{ status = (Str 'released') } }
      updateMask = @{ fieldPaths = @('status') }
    })
  Write-Host "Passenger in seat $LeaveSeat ended their journey (booking $id released)."
  return
}

# ---- -AddSos ------------------------------------------------------------------------------
if ($AddSos) {
  if (-not (Get-Doc 'journey_instances' $JourneyId)) {
    throw "Journey $JourneyId does not exist yet. Run this script once without -AddSos first."
  }
  $stamp = (Get-Date).ToString('yyyyMMddHHmmss')
  # Filed exactly as the passenger app's JourneyProvider.triggerSOS files it (its ids are
  # "SOS_<millis>"; ours keep the demo_ prefix so -Reset can remove it).
  $id = "demo_SOS_live_$stamp"
  $fields = @{
    incident_id           = (Str $id)
    journey_id            = (Str $JourneyId)
    reporter_passenger_id = (Str 'demo_passenger')
    incident_type         = (Str 'unwanted_contact')
    incident_datetime     = (Str (MinutesAgo 0))
    seat_location         = (Str $SosSeat)
    severity_level        = (Str 'high')
    description           = (Str 'SOS triggered by passenger from the Journey tab.')
    action_taken          = (Str 'Conductor notified via FCM - seat and GPS point attached')
    status                = (Str 'escalated')
    resolution_date       = (NullVal)
  }
  Invoke-Commit @((New-Write 'incident_reports' $id $fields))
  Write-Host "SOS raised from seat $SosSeat. The conductor app should pop up an SOS alert now."
  return
}

# ---- -AddMessage --------------------------------------------------------------------------
if ($AddMessage) {
  if (-not (Get-Doc 'journey_instances' $JourneyId)) {
    throw "Journey $JourneyId does not exist yet. Run this script once without -AddMessage first."
  }
  $stamp = (Get-Date).ToString('yyyyMMddHHmmss')
  $id = "demo_msg_live_$stamp"
  $text = if ($MessageText) { $MessageText } else { $messagePresets[(Get-Date).Second % $messagePresets.Count] }
  Invoke-Commit @((New-Write 'conductor_messages' $id (New-MessageFields $id $MessageSeat $text 'sent' (MinutesAgo 0))))
  Write-Host "Message from seat ${MessageSeat}: `"$text`""
  return
}

# ---- -AddIncident -------------------------------------------------------------------------
if ($AddIncident) {
  if (-not (Get-Doc 'journey_instances' $JourneyId)) {
    throw "Journey $JourneyId does not exist yet. Run this script once without -AddIncident first."
  }
  $stamp = (Get-Date).ToString('yyyyMMddHHmmss')
  $id = "demo_inc_live_$stamp"
  $fields = @{
    incident_id           = (Str $id)
    journey_id            = (Str $JourneyId)
    reporter_passenger_id = (Str 'demo_passenger')
    incident_type         = (Str 'verbal_harassment')
    incident_datetime     = (Str (MinutesAgo 0))
    seat_location         = (Str '5C')
    severity_level        = (Str 'high')
    description           = (Str 'Passenger reports repeated verbal abuse from another passenger.')
    action_taken          = (Str 'Notified Conductor')
    status                = (Str 'pending')
    resolution_date       = (NullVal)
  }
  Invoke-Commit @((New-Write 'incident_reports' $id $fields))
  Write-Host 'Added a high-severity incident at seat 5C.'
  return
}

# ---- -AddAllocation -----------------------------------------------------------------------
if ($AddAllocation) {
  if (-not (Get-Doc 'journey_instances' $JourneyId)) {
    throw "Journey $JourneyId does not exist yet. Run this script once without -AddAllocation first."
  }

  $used = @($samples | ForEach-Object { $_.seat })
  $used += @((Get-JourneyDocs 'seat_allocations') | ForEach-Object { $_.fields.seat_number.stringValue })
  $next = $livePool | Where-Object { $used -notcontains $_[0] } | Select-Object -First 1
  if (-not $next) { throw 'The demo seat pool is used up. Run -Reset and seed again.' }

  $seat, $zone, $risk, $boarding, $alighting = $next
  $stamp = (Get-Date).ToString('yyyyMMddHHmmss')
  $allocId = "demo_alloc_live_$stamp"

  $writes = @(
    (New-Write 'seat_allocations' $allocId (New-AllocationFields $seat $risk $boarding $alighting $allocId "demo_bk_live_$stamp" (MinutesAgo 0) $false)),
    # What the passenger app does on every booking: bump current_occupancy by one.
    @{
      transform = @{
        document        = "$docRoot/journey_instances/$JourneyId"
        fieldTransforms = @(@{ fieldPath = 'current_occupancy'; increment = (Int 1) })
      }
    }
  )
  if ($WithCash) {
    $payId = "demo_pay_live_$stamp"
    $writes += (New-Write 'payments' $payId (New-PaymentFields $payId $allocId 'conductor' 'pay_on_board' 'Pay to conductor onboard' (MinutesAgo 0)))
  }
  Invoke-Commit $writes
  $extra = if ($WithCash) { ' + a cash fare to collect' } else { '' }
  Write-Host "Added passenger: seat $seat ($zone), $boarding -> $alighting$extra."
  return
}

# ---- default: create / refresh the demo trip ---------------------------------------------
$existing = Get-Doc 'journey_instances' $JourneyId
if ($existing) {
  $owner = $existing.fields.conductor_id.stringValue
  if ($owner -ne $ConductorId -and -not $Force) {
    throw "journey_instances/$JourneyId already exists and belongs to conductor '$owner', not '$ConductorId'. Re-run with -Force to overwrite it, or choose another -JourneyId."
  }
}

$count = { param($zone) @($samples | Where-Object { $_.zone -eq $zone }).Count }
$journeyFields = @{
  journey_id         = (Str $JourneyId)
  bus_id             = (Str $BusId)
  route_id           = (Str 'R_87')
  conductor_id       = (Str $ConductorId)
  departure_datetime = (Str (MinutesAgo $departedMinutesAgo))
  arrival_datetime   = (Str (Iso ((Get-Date).ToUniversalTime().AddHours(6))))
  current_occupancy  = (Int $sampleCount)
  standing_count     = (Int (& $count 'standing'))
  current_stop       = (Str $currentStop)
  crowding_level     = (Str 'moderate')
  status             = (Str 'in_transit')
  priority_occupied  = (Int (& $count 'priority'))
  general_occupied   = (Int (& $count 'general'))
  limited_occupied   = (Int (& $count 'limited'))
}
$writes = @((New-Write 'journey_instances' $JourneyId $journeyFields))

# Make sure the demo conductor appears in the app's login list. An existing conductor
# document (e.g. one seeded by the passenger app) is left exactly as it is.
if (-not (Get-Doc 'conductors' $ConductorId)) {
  $writes += (New-Write 'conductors' $ConductorId @{
    conductor_id = (Str $ConductorId)
    name         = (Str $ConductorName)
    phone_number = (Str '')
    rating       = (Dbl 4.5)
  })
}

if (-not $NoSamples) {
  $allocIdBySeat = @{}
  foreach ($s in $samples) {
    $n = [int]$s.id.Substring($s.id.Length - 2)
    $allocIdBySeat[$s.seat] = $s.id
    $writes += (New-Write 'seat_allocations' $s.id (New-AllocationFields $s.seat $s.risk $s.boarding $s.alighting $s.id ('demo_bk_{0:d2}' -f $n) (MinutesAgo $s.ago) $s.reserved))
  }

  # Payments: booked a little after each passenger's allocation.
  $p = 0
  $agoBySeat = @{}
  foreach ($s in $samples) { $agoBySeat[$s.seat] = $s.ago }
  $paymentPlans = @()
  foreach ($seat in $cashPending) { $paymentPlans += , @($seat, 'conductor', 'pay_on_board', 'Pay to conductor onboard') }
  foreach ($seat in $cashCollected) { $paymentPlans += , @($seat, 'conductor', 'completed', 'Pay to conductor onboard') }
  foreach ($seat in $cardPaid) { $paymentPlans += , @($seat, 'card', 'completed', 'Card **** 4242') }
  foreach ($plan in $paymentPlans) {
    $p++
    $payId = 'demo_pay_{0:d2}' -f $p
    $when = MinutesAgo ([Math]::Max(0, $agoBySeat[$plan[0]] - 1))
    $writes += (New-Write 'payments' $payId (New-PaymentFields $payId $allocIdBySeat[$plan[0]] $plan[1] $plan[2] $plan[3] $when))
  }

  $incidents = @(
    @{ id = 'demo_inc_01'; type = 'unwanted_contact'; ago = 18; seat = '5B'; severity = 'high'
       desc = 'Passenger reported unwanted physical contact from the adjacent seat occupant.'
       action = 'Notified Conductor'; status = 'pending'; resolved = $false },
    @{ id = 'demo_inc_02'; type = 'verbal_harassment'; ago = 30; seat = '4A'; severity = 'medium'
       desc = 'Repeated inappropriate comments from a passenger seated behind.'
       action = 'Notified Conductor'; status = 'pending'; resolved = $false },
    @{ id = 'demo_inc_03'; type = 'unsafe_crowding'; ago = 100; seat = 'Standing-2'; severity = 'low'
       desc = 'Aisle congested near the rear door at the Negombo Bus Stand stop.'
       action = 'Conductor asked passengers to move back'; status = 'resolved'; resolved = $true }
  )
  # Passenger messages ("Text conductor"): two unread, one already read.
  $seedMessages = @(
    @('demo_msg_01', '4B', $messagePresets[0], 'sent', 25),
    @('demo_msg_02', '9E', $messagePresets[1], 'sent', 12),
    @('demo_msg_03', '7C', $messagePresets[3], 'read', 60)
  )
  foreach ($m in $seedMessages) {
    $writes += (New-Write 'conductor_messages' $m[0] (New-MessageFields $m[0] $m[1] $m[2] $m[3] (MinutesAgo $m[4])))
  }

  foreach ($inc in $incidents) {
    $fields = @{
      incident_id           = (Str $inc.id)
      journey_id            = (Str $JourneyId)
      reporter_passenger_id = (Str 'demo_passenger')
      incident_type         = (Str $inc.type)
      incident_datetime     = (Str (MinutesAgo $inc.ago))
      seat_location         = (Str $inc.seat)
      severity_level        = (Str $inc.severity)
      description           = (Str $inc.desc)
      action_taken          = (Str $inc.action)
      status                = (Str $inc.status)
      resolution_date       = $(if ($inc.resolved) { Str (MinutesAgo ($inc.ago - 5)) } else { NullVal })
    }
    $writes += (New-Write 'incident_reports' $inc.id $fields)
  }
}

Invoke-Commit $writes

Write-Host "Demo trip ready: journey_instances/$JourneyId (conductor $ConductorId, bus $BusId, route R_87, at $currentStop)"
if ($NoSamples) {
  Write-Host 'No passengers, payments or incidents written (-NoSamples).'
} else {
  Write-Host "Wrote $sampleCount passengers, $($paymentPlans.Count) payments, 3 incident reports and 3 messages (ids start with demo_)."
}
Write-Host ''
Write-Host "Open the app and pick '$ConductorName' ($ConductorId) on the login screen to see it."
Write-Host 'Live demo:  powershell -File tool\seed_demo_journey.ps1 -AddAllocation -WithCash'
Write-Host '            powershell -File tool\seed_demo_journey.ps1 -AddIncident'
Write-Host '            powershell -File tool\seed_demo_journey.ps1 -AddSos            (pop-up alert)'
Write-Host '            powershell -File tool\seed_demo_journey.ps1 -AddMessage        (Messages page)'
Write-Host '            powershell -File tool\seed_demo_journey.ps1 -EndJourney        (seat empties + offer to a standing passenger)'
Write-Host 'Clean up:   powershell -File tool\seed_demo_journey.ps1 -Reset'
