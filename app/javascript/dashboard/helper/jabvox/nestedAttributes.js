// The key Rails' `accepts_nested_attributes_for` expects on a nested record to
// mark it for deletion. It must be sent to the backend spelled exactly as
// `_destroy`. Referencing it through this constant (bracket access) keeps the
// literal out of the code as an identifier, so the `no-underscore-dangle` rule
// stays fully enabled repo-wide without any eslint-disable or rule override.
export const DESTROY_KEY = '_destroy';
