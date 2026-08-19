<?php
/**
 * FPI CRM JSON API — reads synced SQLite DB
 */
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');

$dbPath = __DIR__ . '/data/fpi_crm.db';
if (!is_readable($dbPath)) {
    http_response_code(503);
    echo json_encode(['ok' => false, 'error' => 'CRM database not available. Run sync_crm_to_web.py as root.']);
    exit;
}

try {
    $db = new SQLite3($dbPath, SQLITE3_OPEN_READONLY);
    $db->busyTimeout(3000);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'SQLite open failed', 'detail' => $e->getMessage()]);
    exit;
}

function row_to_array(SQLite3Result $res): array {
    $out = [];
    while ($r = $res->fetchArray(SQLITE3_ASSOC)) {
        $out[] = $r;
    }
    return $out;
}

function decode_json_field($v) {
    if ($v === null || $v === '') return [];
    $j = json_decode($v, true);
    return is_array($j) ? $j : [];
}

function enrich(array $lead): array {
    $phones = decode_json_field($lead['phones_json'] ?? '[]');
    $emails = decode_json_field($lead['emails_json'] ?? '[]');
    $lead['phone_display'] = $lead['phone_primary'] ?: ($phones[0] ?? '');
    $lead['email_display'] = $lead['email_primary'] ?: ($emails[0] ?? '');
    $lead['phones'] = $phones;
    $lead['emails'] = $emails;
    $g = strtolower(trim((string)($lead['garage_type'] ?? '')));
    if ($g === '' || $g === 'unknown') {
        $lead['garage_label'] = 'Unknown';
    } elseif ($g === 'none' || $g === 'no' || $g === 'n') {
        $lead['garage_label'] = 'No garage';
    } elseif ($g === 'attached') {
        $sp = $lead['garage_spaces'] ?? '';
        $lead['garage_label'] = 'Attached' . ($sp !== '' && $sp !== null ? " ({$sp}-car)" : '');
    } elseif ($g === 'detached') {
        $sp = $lead['garage_spaces'] ?? '';
        $lead['garage_label'] = 'Detached' . ($sp !== '' && $sp !== null ? " ({$sp}-car)" : '');
    } else {
        $lead['garage_label'] = $lead['garage_type'];
    }
    $status_labels = [
        'NEW_LISA_LEAD' => 'New Lisa Lead',
        'APPROVED_LEAD_SENDING_ALEX' => 'Approved → Alex',
        'CURR_ALEX' => 'Curr Alex',
        'SCOUTING_LEAD' => 'Scouting Lead',
        'WAITING_MAX_PRICE_SHANE' => 'Waiting Max Price (SHANE)',
        'ALEX_MANAGING' => 'Alex managing',
        'CLIENT_APPROVED_CONTRACT_PENDING' => 'Contract pending',
        'CONTRACT_SIGNED' => 'Contract signed',
        'FINDING_FLIPPER' => 'Finding flipper',
        'ASSIGNED_TO_FLIPPER' => 'Assigned to flipper',
        'CLOSED' => 'Closed',
        'SUPPRESSED' => 'Suppressed',
        'DISQUALIFIED' => 'Disqualified',
        'DEAD' => 'Dead',
        'NURTURE' => 'Nurture',
    ];
    $st = $lead['status'] ?? '';
    $lead['status_label'] = $status_labels[$st] ?? $st;
    return $lead;
}

$action = $_GET['action'] ?? 'list';
$id = $_GET['id'] ?? '';

if ($action === 'list') {
    $q = $db->query('SELECT * FROM leads ORDER BY updated_at DESC');
    $leads = array_map('enrich', row_to_array($q));
    $counts = [];
    $cq = $db->query('SELECT status, COUNT(*) AS c FROM leads GROUP BY status');
    while ($r = $cq->fetchArray(SQLITE3_ASSOC)) {
        $counts[$r['status']] = (int)$r['c'];
    }
    echo json_encode([
        'ok' => true,
        'generated_at' => gmdate('c'),
        'counts' => $counts,
        'leads' => $leads,
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

if ($action === 'get' && $id !== '') {
    $stmt = $db->prepare('SELECT * FROM leads WHERE id = :id');
    $stmt->bindValue(':id', $id, SQLITE3_TEXT);
    $res = $stmt->execute();
    $lead = $res->fetchArray(SQLITE3_ASSOC);
    if (!$lead) {
        http_response_code(404);
        echo json_encode(['ok' => false, 'error' => 'Lead not found']);
        exit;
    }
    $lead = enrich($lead);

    $h = $db->prepare('SELECT * FROM status_history WHERE lead_id = :id ORDER BY at DESC LIMIT 30');
    $h->bindValue(':id', $id, SQLITE3_TEXT);
    $hist = row_to_array($h->execute());

    $a = $db->prepare('SELECT * FROM activities WHERE lead_id = :id ORDER BY at DESC LIMIT 40');
    $a->bindValue(':id', $id, SQLITE3_TEXT);
    $acts = row_to_array($a->execute());

    echo json_encode([
        'ok' => true,
        'lead' => $lead,
        'status_history' => $hist,
        'activities' => $acts,
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

if ($action === 'pipeline') {
    $q = $db->query('SELECT status, COUNT(*) AS c FROM leads GROUP BY status ORDER BY c DESC');
    echo json_encode(['ok' => true, 'pipeline' => row_to_array($q)]);
    exit;
}

http_response_code(400);
echo json_encode(['ok' => false, 'error' => 'Unknown action']);
