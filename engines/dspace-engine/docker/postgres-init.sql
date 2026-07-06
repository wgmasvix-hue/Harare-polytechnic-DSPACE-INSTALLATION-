-- =============================================================================
--  DSpace PostgreSQL Initialization
--  Runs automatically when the database container first starts
-- =============================================================================

-- Enable pgcrypto (required by DSpace for UUID generation)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Set timezone to Africa/Harare (adjust for your region)
SET timezone = 'UTC';
