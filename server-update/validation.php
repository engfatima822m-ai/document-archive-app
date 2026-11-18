<?php
declare(strict_types=1);

require_once __DIR__ . DIRECTORY_SEPARATOR . 'bootstrap.php';

function validation_error(string $message): never
{
    json_response(
        [
            'success' => false,
            'message' => $message,
        ],
        422
    );
}

function text_length(string $value): int
{
    return function_exists('mb_strlen')
        ? mb_strlen($value, 'UTF-8')
        : strlen($value);
}

function normalize_text(
    string $value,
    bool $allowNewLines = false
): string {
    $value = str_replace(["\r\n", "\r"], "\n", $value);
    $value = trim($value);

    if ($allowNewLines) {
        $cleaned = preg_replace(
            '/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u',
            '',
            $value
        );
    } else {
        $value = str_replace(["\n", "\t"], ' ', $value);

        $cleaned = preg_replace(
            '/[\x00-\x1F\x7F]/u',
            '',
            $value
        );

        if (is_string($cleaned)) {
            $cleaned = preg_replace(
                '/\s+/u',
                ' ',
                $cleaned
            );
        }
    }

    return is_string($cleaned)
        ? trim($cleaned)
        : '';
}

function required_text(
    array $data,
    string $key,
    string $label,
    int $maximumLength,
    bool $allowNewLines = false
): string {
    $rawValue = $data[$key] ?? null;

    if (!is_string($rawValue)) {
        validation_error("$label مطلوب.");
    }

    $value = normalize_text(
        $rawValue,
        $allowNewLines
    );

    if ($value === '') {
        validation_error("$label مطلوب.");
    }

    if (text_length($value) > $maximumLength) {
        validation_error(
            "$label يتجاوز الحد المسموح وهو "
            . "$maximumLength حرفًا."
        );
    }

    return $value;
}

function optional_text(
    array $data,
    string $key,
    string $label,
    int $maximumLength,
    bool $allowNewLines = false
): ?string {
    $rawValue = $data[$key] ?? null;

    if ($rawValue === null || $rawValue === '') {
        return null;
    }

    if (!is_string($rawValue)) {
        validation_error("$label غير صحيح.");
    }

    $value = normalize_text(
        $rawValue,
        $allowNewLines
    );

    if ($value === '') {
        return null;
    }

    if (text_length($value) > $maximumLength) {
        validation_error(
            "$label يتجاوز الحد المسموح وهو "
            . "$maximumLength حرفًا."
        );
    }

    return $value;
}

function required_positive_integer(
    array $data,
    string $key,
    string $label
): int {
    $value = filter_var(
        $data[$key] ?? null,
        FILTER_VALIDATE_INT,
        [
            'options' => [
                'min_range' => 1,
            ],
        ]
    );

    if ($value === false) {
        validation_error("$label غير صحيح.");
    }

    return (int) $value;
}

function required_version(array $data): int
{
    return required_positive_integer(
        $data,
        'version',
        'رقم إصدار السجل'
    );
}

function validate_date_value(
    string $value,
    string $label
): string {
    $date = DateTimeImmutable::createFromFormat(
        '!Y-m-d',
        $value
    );

    $errors = DateTimeImmutable::getLastErrors();

    $hasErrors = is_array($errors)
        && (
            $errors['warning_count'] > 0
            || $errors['error_count'] > 0
        );

    if (
        $date === false
        || $hasErrors
        || $date->format('Y-m-d') !== $value
    ) {
        validation_error(
            "$label يجب أن يكون بصيغة YYYY-MM-DD."
        );
    }

    return $value;
}

function required_date(
    array $data,
    string $key,
    string $label
): string {
    $value = required_text(
        $data,
        $key,
        $label,
        10
    );

    return validate_date_value(
        $value,
        $label
    );
}

function optional_date(
    array $data,
    string $key,
    string $label
): ?string {
    $value = optional_text(
        $data,
        $key,
        $label,
        10
    );

    if ($value === null) {
        return null;
    }

    return validate_date_value(
        $value,
        $label
    );
}

function required_document_status(array $data): string
{
    $status = required_text(
        $data,
        'status',
        'حالة الملف',
        30
    );

    $allowedStatuses = [
        'قيد الإنجاز',
        'منجز',
        'تم الاطلاع',
    ];

    if (!in_array($status, $allowedStatuses, true)) {
        validation_error(
            'حالة الملف غير مسموحة.'
        );
    }

    return $status;
}

function validate_relative_path(
    string $path,
    string $label = 'مسار الملف'
): string {
    $path = trim(
        str_replace('\\', '/', $path)
    );

    $path = trim($path, '/');

    if (
        $path === ''
        || text_length($path) > 500
    ) {
        validation_error("$label غير صحيح.");
    }

    if (
        preg_match('/^[A-Za-z]:/u', $path)
        || str_contains($path, "\0")
    ) {
        validation_error(
            "$label يجب أن يكون نسبيًا."
        );
    }

    $segments = explode('/', $path);
    $cleanSegments = [];

    $reservedNames = [
        'CON',
        'PRN',
        'AUX',
        'NUL',
        'COM1',
        'COM2',
        'COM3',
        'COM4',
        'COM5',
        'COM6',
        'COM7',
        'COM8',
        'COM9',
        'LPT1',
        'LPT2',
        'LPT3',
        'LPT4',
        'LPT5',
        'LPT6',
        'LPT7',
        'LPT8',
        'LPT9',
    ];

    foreach ($segments as $segment) {
        $segment = trim($segment);

        if (
            $segment === ''
            || $segment === '.'
            || $segment === '..'
        ) {
            validation_error(
                "$label يحتوي جزءًا غير مسموح."
            );
        }

        if (
            preg_match(
                '/[<>:"|?*\x00-\x1F]/u',
                $segment
            )
            || str_ends_with($segment, '.')
            || str_ends_with($segment, ' ')
        ) {
            validation_error(
                "$label يحتوي رموزًا غير مسموحة."
            );
        }

        $baseName = strtoupper(
            explode('.', $segment, 2)[0]
        );

        if (
            in_array(
                $baseName,
                $reservedNames,
                true
            )
        ) {
            validation_error(
                "$label يحتوي اسمًا محجوزًا."
            );
        }

        if (text_length($segment) > 180) {
            validation_error(
                "أحد أجزاء $label أطول من الحد المسموح."
            );
        }

        $cleanSegments[] = $segment;
    }

    return implode('/', $cleanSegments);
}

function required_relative_path(
    array $data,
    string $key = 'relative_folder_path',
    string $label = 'مسار المجلد'
): string {
    $value = required_text(
        $data,
        $key,
        $label,
        500
    );

    return validate_relative_path(
        $value,
        $label
    );
}

/*
|--------------------------------------------------------------------------
| التحقق من بيانات PDF
|--------------------------------------------------------------------------
*/

function validate_pdf_payload(array $data): array
{
    $pdf = $data['pdf'] ?? null;

    if (!is_array($pdf)) {
        validation_error(
            'بيانات ملف PDF مطلوبة.'
        );
    }

    $relativePath = required_text(
        $pdf,
        'relative_path',
        'مسار ملف PDF',
        500
    );

    $relativePath = validate_relative_path(
        $relativePath,
        'مسار ملف PDF'
    );

    $pageCount = required_positive_integer(
        $pdf,
        'page_count',
        'عدد صفحات ملف PDF'
    );

    if ($pageCount > 2000) {
        validation_error(
            'عدد صفحات ملف PDF يتجاوز الحد المسموح.'
        );
    }

    $sha256 = optional_text(
        $pdf,
        'sha256',
        'بصمة ملف PDF',
        64
    );

    if (
        $sha256 !== null
        && preg_match(
            '/^[a-f0-9]{64}$/i',
            $sha256
        ) !== 1
    ) {
        validation_error(
            'بصمة ملف PDF غير صحيحة.'
        );
    }

    return [
        'relative_path' => $relativePath,
        'page_count' => $pageCount,
        'sha256' => $sha256 === null
            ? null
            : strtolower($sha256),
    ];
}

/*
|--------------------------------------------------------------------------
| وضع السحب ومعرّف دفعة السحب
|--------------------------------------------------------------------------
*/

function validate_scan_mode(
    array $data,
    int $pageCount
): array {
    $rawMode = $data['scan_mode']
        ?? 'single_document';

    if (!is_string($rawMode)) {
        validation_error(
            'طريقة السحب غير صحيحة.'
        );
    }

    $scanMode = normalize_text($rawMode);

    $allowedModes = [
        'single_document',
        'separate_pages',
    ];

    if (!in_array($scanMode, $allowedModes, true)) {
        validation_error(
            'طريقة السحب غير مسموحة.'
        );
    }

    $scanBatchId = optional_text(
        $data,
        'scan_batch_id',
        'معرّف دفعة السحب',
        36
    );

    if (
        $scanBatchId !== null
        && preg_match(
            '/^[a-f0-9]{8}-[a-f0-9]{4}-'
            . '[1-5][a-f0-9]{3}-'
            . '[89ab][a-f0-9]{3}-'
            . '[a-f0-9]{12}$/i',
            $scanBatchId
        ) !== 1
    ) {
        validation_error(
            'معرّف دفعة السحب غير صحيح.'
        );
    }

    if ($scanMode === 'separate_pages') {
        if ($pageCount !== 1) {
            validation_error(
                'في وضع فصل الأوراق يجب أن يحتوي '
                . 'كل ملف PDF على صفحة واحدة.'
            );
        }

        if ($scanBatchId === null) {
            validation_error(
                'معرّف دفعة السحب مطلوب عند فصل الأوراق.'
            );
        }
    }

    if ($scanMode === 'single_document') {
        $scanBatchId = null;
    }

    return [
        'scan_mode' => $scanMode,
        'scan_batch_id' => $scanBatchId,
    ];
}

function validated_search_query(): string
{
    $query = normalize_text(
        (string) (
            $_GET['query']
            ?? $_GET['q']
            ?? ''
        )
    );

    if ($query === '') {
        validation_error(
            'اكتبي كلمة للبحث.'
        );
    }

    if (text_length($query) > 100) {
        validation_error(
            'عبارة البحث أطول من الحد المسموح.'
        );
    }

    return $query;
}

function pagination_values(): array
{
    $page = filter_var(
        $_GET['page'] ?? 1,
        FILTER_VALIDATE_INT,
        [
            'options' => [
                'default' => 1,
                'min_range' => 1,
            ],
        ]
    );

    $perPage = filter_var(
        $_GET['per_page'] ?? 25,
        FILTER_VALIDATE_INT,
        [
            'options' => [
                'default' => 25,
                'min_range' => 1,
                'max_range' => 100,
            ],
        ]
    );

    return [
        'page' => (int) $page,
        'per_page' => (int) $perPage,
        'offset' =>
            ((int) $page - 1) * (int) $perPage,
    ];
}