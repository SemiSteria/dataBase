-- ============================================
-- BeeFootFlow - Schema PostgreSQL Optimisé
-- Baby-foot tracker 1v1 / 2v2
-- ============================================

SELECT 'CREATE DATABASE "BeeFootFlow" TEMPLATE template0'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'BeeFootFlow'
)\gexec
\c BeeFootFlow

-- Extension pour UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enum pour le statut des matchs
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'match_status') THEN
        CREATE TYPE match_status AS ENUM ('pending', 'in_progress', 'finished');
    END IF;
END
$$;

-- ============================================
-- TABLE : users
-- ============================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pseudo VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    elo INTEGER NOT NULL DEFAULT 1000,
    elo_peak INTEGER NOT NULL DEFAULT 1000,
    mmr INTEGER NOT NULL DEFAULT 1000,
    total_matches INTEGER NOT NULL DEFAULT 0,
    total_wins INTEGER NOT NULL DEFAULT 0,
    total_goals INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================
-- TABLE : matches
-- ============================================
CREATE TABLE IF NOT EXISTS matches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    score_team_a INTEGER NOT NULL DEFAULT 0 CHECK (score_team_a <= 10),
    score_team_b INTEGER NOT NULL DEFAULT 0 CHECK (score_team_b <= 10),
    goal_limit INTEGER NOT NULL DEFAULT 10,
    avg_ball_speed DECIMAL(6,2),
    avg_time_between_goals INTEGER,
    avg_elo DECIMAL(8,2),
    duration INTEGER,
    status match_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMP
);

-- ============================================
-- TABLE : match_players
-- ============================================
CREATE TABLE IF NOT EXISTS match_players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    match_id UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team VARCHAR(1) NOT NULL CHECK (team IN ('A','B')),
    UNIQUE(match_id, user_id)
);

-- ============================================
-- TABLE : goals
-- ============================================
CREATE TABLE IF NOT EXISTS goals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    match_id UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    team VARCHAR(1) NOT NULL CHECK (team IN ('A','B')),
    ball_speed DECIMAL(6,2),
    time_since_last_goal INTEGER,
    scored_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================
-- INDEX
-- ============================================
CREATE INDEX IF NOT EXISTS idx_match_players_match ON match_players(match_id);
CREATE INDEX IF NOT EXISTS idx_match_players_user ON match_players(user_id);
CREATE INDEX IF NOT EXISTS idx_goals_match ON goals(match_id);
CREATE INDEX IF NOT EXISTS idx_users_elo ON users(elo DESC);
CREATE INDEX IF NOT EXISTS idx_matches_status ON matches(status);
CREATE INDEX IF NOT EXISTS idx_matches_created ON matches(created_at DESC);

-- ============================================
-- TRIGGER : mise à jour automatique stats, Elo, peak Elo et MMR
-- ============================================
CREATE OR REPLACE FUNCTION update_user_stats()
RETURNS TRIGGER AS $$
DECLARE
    winner_team CHAR;
    rec RECORD;
    new_elo INTEGER;
BEGIN
    IF NEW.status = 'finished' THEN
        -- Déterminer l'équipe gagnante
        IF NEW.score_team_a > NEW.score_team_b THEN
            winner_team := 'A';
        ELSIF NEW.score_team_b > NEW.score_team_a THEN
            winner_team := 'B';
        ELSE
            winner_team := NULL;
        END IF;

        FOR rec IN SELECT * FROM match_players WHERE match_id = NEW.id LOOP
            -- total_matches
            UPDATE users SET total_matches = total_matches + 1 WHERE id = rec.user_id;

            -- total_wins
            IF rec.team = winner_team THEN
                UPDATE users SET total_wins = total_wins + 1 WHERE id = rec.user_id;
            END IF;

            -- total_goals
            IF rec.team = 'A' THEN
                UPDATE users SET total_goals = total_goals + NEW.score_team_a WHERE id = rec.user_id;
            ELSE
                UPDATE users SET total_goals = total_goals + NEW.score_team_b WHERE id = rec.user_id;
            END IF;

            -- Elo simple +10/-10 et mise à jour peak Elo et MMR
            IF winner_team IS NOT NULL THEN
                SELECT elo INTO new_elo FROM users WHERE id = rec.user_id;
                IF rec.team = winner_team THEN
                    new_elo := new_elo + 10;
                ELSE
                    new_elo := GREATEST(0, new_elo - 10);
                END IF;

                UPDATE users SET
                    elo = new_elo,
                    elo_peak = GREATEST(elo_peak, new_elo),
                    mmr = new_elo,
                    updated_at = NOW()
                WHERE id = rec.user_id;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_user_stats
AFTER UPDATE OF status ON matches
FOR EACH ROW
WHEN (NEW.status = 'finished')
EXECUTE FUNCTION update_user_stats();

-- ============================================
-- VUE : leaderboard
-- ============================================
CREATE OR REPLACE VIEW leaderboard AS
SELECT
    u.id,
    u.pseudo,
    u.elo,
    u.elo_peak,
    u.mmr,
    u.total_matches,
    u.total_wins,
    u.total_goals,
    CASE WHEN u.total_matches > 0 THEN ROUND((u.total_wins::DECIMAL / u.total_matches) * 100,1) ELSE 0 END AS win_rate
FROM users u
ORDER BY u.elo DESC;

-- ============================================
-- VUE : résumé match
-- ============================================
CREATE OR REPLACE VIEW match_summary AS
SELECT
    m.id AS match_id,
    m.score_team_a,
    m.score_team_b,
    m.avg_ball_speed,
    m.avg_elo,
    m.duration,
    m.status,
    m.created_at,
    m.finished_at,
    (SELECT COUNT(*) FROM goals g WHERE g.match_id = m.id) AS total_goals,
    (SELECT AVG(g.ball_speed) FROM goals g WHERE g.match_id = m.id) AS avg_goal_speed,
    (SELECT AVG(g.time_since_last_goal) FROM goals g WHERE g.match_id = m.id AND g.time_since_last_goal IS NOT NULL) AS avg_time_between_goals
FROM matches m;