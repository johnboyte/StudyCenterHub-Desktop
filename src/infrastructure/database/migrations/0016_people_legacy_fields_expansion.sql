-- Migration 0016: Expand people table with legacy profile fields for complete editing & UI/UX parity

ALTER TABLE people ADD COLUMN suffix TEXT;
ALTER TABLE people ADD COLUMN email TEXT;
ALTER TABLE people ADD COLUMN school_email TEXT;
ALTER TABLE people ADD COLUMN preferred_email TEXT DEFAULT 'Main';
ALTER TABLE people ADD COLUMN birthday TEXT;
ALTER TABLE people ADD COLUMN flag_status TEXT DEFAULT 'Clear';
ALTER TABLE people ADD COLUMN sms_consent INTEGER DEFAULT 1;
ALTER TABLE people ADD COLUMN sms_consent_given INTEGER DEFAULT 1;
ALTER TABLE people ADD COLUMN home_address_street TEXT;
ALTER TABLE people ADD COLUMN home_address_line2 TEXT;
ALTER TABLE people ADD COLUMN home_address_city TEXT;
ALTER TABLE people ADD COLUMN home_address_state TEXT;
ALTER TABLE people ADD COLUMN home_address_zip TEXT;
ALTER TABLE people ADD COLUMN school_address_street TEXT;
ALTER TABLE people ADD COLUMN school_address_line2 TEXT;
ALTER TABLE people ADD COLUMN school_address_city TEXT;
ALTER TABLE people ADD COLUMN school_address_state TEXT;
ALTER TABLE people ADD COLUMN school_address_zip TEXT;
ALTER TABLE people ADD COLUMN primary_role TEXT DEFAULT 'Participant';
ALTER TABLE people ADD COLUMN qr_status TEXT DEFAULT 'Not Issued';
ALTER TABLE people ADD COLUMN pin_status TEXT DEFAULT 'Not Set';
ALTER TABLE people ADD COLUMN emergency_contact_relationship TEXT;
