CREATE TABLE threads (
    tid INT PRIMARY KEY,
    forum_id INT NOT NULL,
    topic TEXT
);
CREATE TABLE posts (
    pid INT PRIMARY KEY,
    topic INT NOT NULL,
    seq INT NOT NULL,
    author TEXT NOT NULL,
    utime INTEGER NOT NULL,
    edit_count INT DEFAULT 0,
    edit_user TEXT,
    edit_time INT,
    post_title TEXT,
    content TEXT,
    signature TEXT
);
CREATE TABLE users (
    username TEXT PRIMARY KEY,
    join_date INT NOT NULL,
    post_count INT NOT NULL,
    rank TEXT
);
CREATE TABLE bogusthreads (
    tid INT PRIMARY KEY
);
CREATE TABLE unauthorized (
    tid INT PRIMARY KEY
);
-- Tapatalk calls anon users 'Guest', and we don't want to look for their info so as to avoid script dying in a fire lol
INSERT INTO users VALUES ('Guest', 0, 0, 'undef');