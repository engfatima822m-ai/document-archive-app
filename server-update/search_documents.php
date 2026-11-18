<?php
declare(strict_types=1);

require_once __DIR__
    . DIRECTORY_SEPARATOR
    . 'auth.php';

require_method('GET');

$user = authenticated_user();
require_password_changed($user);

$query = validated_search_query();
$pagination = pagination_values();

$page = $pagination['page'];
$perPage = $pagination['per_page'];
$offset = $pagination['offset'];

/*
|--------------------------------------------------------------------------
| حماية LIKE من الرموز الخاصة
|--------------------------------------------------------------------------
*/

$escapedQuery = str_replace(
    ['!', '%', '_'],
    ['!!', '!%', '!_'],
    $query
);

$like = '%' . $escapedQuery . '%';

$connection = db();

/*
|--------------------------------------------------------------------------
| شروط البحث
|--------------------------------------------------------------------------
*/

$searchCondition = '
    (
        documents.document_number
            LIKE ? ESCAPE \'!\'
        OR documents.document_title
            LIKE ? ESCAPE \'!\'
        OR documents.notes
            LIKE ? ESCAPE \'!\'
        OR documents.status
            LIKE ? ESCAPE \'!\'
        OR documents.reminder_note
            LIKE ? ESCAPE \'!\'
        OR document_attachments.sub_document_number
            LIKE ? ESCAPE \'!\'
        OR document_attachments.sub_document_title
            LIKE ? ESCAPE \'!\'
        OR document_attachments.notes
            LIKE ? ESCAPE \'!\'
        OR document_attachments.reminder_note
            LIKE ? ESCAPE \'!\'
    )
';

/*
|--------------------------------------------------------------------------
| حساب عدد الملفات الرئيسية المطابقة
|--------------------------------------------------------------------------
*/

$searchTypes = str_repeat('s', 9);
$searchValues = array_fill(0, 9, $like);

if (preg_match('/^[0-9٠-٩۰-۹]$/u', $query) === 1) {
    $searchCondition = '(
        documents.document_number = ?
        OR document_attachments.sub_document_number = ?
    )';
    $searchTypes = 'ss';
    $searchValues = [$query, $query];
}

$countSql = '
    SELECT COUNT(DISTINCT documents.id) AS total

    FROM documents

    LEFT JOIN document_attachments
        ON document_attachments.parent_document_id
            = documents.id

    WHERE ' . $searchCondition;

$countStatement = $connection->prepare(
    $countSql
);

$countStatement->bind_param(
    $searchTypes,
    ...$searchValues
);

$countStatement->execute();

$countResult =
    $countStatement->get_result();

$countRow = $countResult->fetch_assoc();

$totalGroups = (int) (
    $countRow['total'] ?? 0
);

$countStatement->close();

/*
|--------------------------------------------------------------------------
| جلب معرّفات الملفات المطابقة
|--------------------------------------------------------------------------
*/

$idSql = '
    SELECT DISTINCT
        documents.id,
        documents.document_date

    FROM documents

    LEFT JOIN document_attachments
        ON document_attachments.parent_document_id
            = documents.id

    WHERE ' . $searchCondition . '

    ORDER BY
        documents.document_date DESC,
        documents.id DESC

    LIMIT ? OFFSET ?
';

$idStatement = $connection->prepare(
    $idSql
);

$pageValues = [...$searchValues, $perPage, $offset];
$idStatement->bind_param(
    $searchTypes . 'ii',
    ...$pageValues
);

$idStatement->execute();

$idResult = $idStatement->get_result();
$documentIds = [];

while ($row = $idResult->fetch_assoc()) {
    $documentIds[] = (int) $row['id'];
}

$idStatement->close();

/*
|--------------------------------------------------------------------------
| تجهيز بيانات الملف الرئيسي
|--------------------------------------------------------------------------
*/

function search_main_document_row(
    array $row
): array {
    return [
        'id' => (int) $row['id'],
        'record_type' => 'main',
        'document_number' =>
            (string) $row['document_number'],
        'document_date' =>
            (string) $row['document_date'],
        'document_title' =>
            (string) $row['document_title'],
        'notes' => $row['notes'] === null
            ? null
            : (string) $row['notes'],
        'status' => (string) $row['status'],
        'reminder_date' =>
            $row['reminder_date'] === null
                ? null
                : (string) $row['reminder_date'],
        'reminder_note' =>
            $row['reminder_note'] === null
                ? null
                : (string) $row['reminder_note'],
        'has_pdf' =>
            $row['pdf_relative_path'] !== null
            && $row['pdf_relative_path'] !== '',
        'pdf_size_bytes' =>
            $row['pdf_size_bytes'] === null
                ? null
                : (int) $row['pdf_size_bytes'],
        'pdf_sha256' =>
            $row['pdf_sha256'] === null
                ? null
                : (string) $row['pdf_sha256'],
        'page_count' =>
            $row['page_count'] === null
                ? null
                : (int) $row['page_count'],
        'scan_mode' =>
            (string) $row['scan_mode'],
        'scan_batch_id' =>
            $row['scan_batch_id'] === null
                ? null
                : (string) $row['scan_batch_id'],
        'version' => (int) $row['version'],
        'created_at' =>
            (string) $row['created_at'],
        'updated_at' =>
            (string) $row['updated_at'],
    ];
}

/*
|--------------------------------------------------------------------------
| تجهيز بيانات الكتاب التابع
|--------------------------------------------------------------------------
*/

function search_attachment_row(
    array $row
): array {
    return [
        'id' => (int) $row['id'],
        'record_type' => 'attachment',
        'parent_document_id' =>
            (int) $row['parent_document_id'],
        'sub_document_number' =>
            (string) $row['sub_document_number'],
        'sub_document_date' =>
            (string) $row['sub_document_date'],
        'sub_document_title' =>
            (string) $row['sub_document_title'],
        'notes' => $row['notes'] === null
            ? null
            : (string) $row['notes'],
        'reminder_date' =>
            $row['reminder_date'] === null
                ? null
                : (string) $row['reminder_date'],
        'reminder_note' =>
            $row['reminder_note'] === null
                ? null
                : (string) $row['reminder_note'],
        'has_pdf' =>
            $row['pdf_relative_path'] !== null
            && $row['pdf_relative_path'] !== '',
        'pdf_size_bytes' =>
            $row['pdf_size_bytes'] === null
                ? null
                : (int) $row['pdf_size_bytes'],
        'pdf_sha256' =>
            $row['pdf_sha256'] === null
                ? null
                : (string) $row['pdf_sha256'],
        'page_count' =>
            $row['page_count'] === null
                ? null
                : (int) $row['page_count'],
        'scan_mode' =>
            (string) $row['scan_mode'],
        'scan_batch_id' =>
            $row['scan_batch_id'] === null
                ? null
                : (string) $row['scan_batch_id'],
        'version' => (int) $row['version'],
        'created_at' =>
            (string) $row['created_at'],
        'updated_at' =>
            (string) $row['updated_at'],
    ];
}

/*
|--------------------------------------------------------------------------
| تحضير استعلامات التفاصيل
|--------------------------------------------------------------------------
*/

$documentStatement = $connection->prepare(
    'SELECT
        id,
        document_number,
        document_date,
        document_title,
        notes,
        status,
        reminder_date,
        reminder_note,
        pdf_relative_path,
        pdf_size_bytes,
        pdf_sha256,
        page_count,
        scan_mode,
        scan_batch_id,
        version,
        created_at,
        updated_at
     FROM documents
     WHERE id = ?
     LIMIT 1'
);

$attachmentsStatement = $connection->prepare(
    'SELECT
        id,
        parent_document_id,
        sub_document_number,
        sub_document_date,
        sub_document_title,
        notes,
        reminder_date,
        reminder_note,
        pdf_relative_path,
        pdf_size_bytes,
        pdf_sha256,
        page_count,
        scan_mode,
        scan_batch_id,
        version,
        created_at,
        updated_at
     FROM document_attachments
     WHERE parent_document_id = ?
     ORDER BY
        sub_document_date DESC,
        id DESC'
);

$groups = [];

foreach ($documentIds as $documentId) {
    $documentStatement->bind_param(
        'i',
        $documentId
    );

    $documentStatement->execute();

    $documentResult =
        $documentStatement->get_result();

    $documentRow =
        $documentResult->fetch_assoc();

    $documentResult->free();

    if (!$documentRow) {
        continue;
    }

    $attachmentsStatement->bind_param(
        'i',
        $documentId
    );

    $attachmentsStatement->execute();

    $attachmentsResult =
        $attachmentsStatement->get_result();

    $attachments = [];

    while (
        $attachmentRow =
            $attachmentsResult->fetch_assoc()
    ) {
        $attachments[] =
            search_attachment_row(
                $attachmentRow
            );
    }

    $attachmentsResult->free();

    $groups[] = [
        'parent' =>
            search_main_document_row(
                $documentRow
            ),
        'attachments' => $attachments,
    ];
}

$documentStatement->close();
$attachmentsStatement->close();

$totalPages = $totalGroups === 0
    ? 0
    : (int) ceil(
        $totalGroups / $perPage
    );

json_response(
    [
        'success' => true,
        'query' => $query,
        'count' => count($groups),
        'groups' => $groups,
        'pagination' => [
            'page' => $page,
            'per_page' => $perPage,
            'total_items' => $totalGroups,
            'total_pages' => $totalPages,
            'has_previous_page' =>
                $page > 1,
            'has_next_page' =>
                $page < $totalPages,
        ],
    ]
);