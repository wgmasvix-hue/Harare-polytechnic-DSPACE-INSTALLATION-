-- DSpace PostgreSQL initialization
-- This runs automatically when the database container first starts

-- Enable pgcrypto (required by DSpace for UUID generation)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Set timezone
SET timezone = 'Africa/Harare';
