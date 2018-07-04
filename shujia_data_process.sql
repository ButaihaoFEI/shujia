USE shujia;


-- 插入csv 数据到表中
DROP TABLE IF EXISTS dw_tb_problem_score_v1;
CREATE external TABLE IF NOT EXISTS dw_tb_problem_score_v1(
	examid STRING COMMENT '试卷ID',
	studentid STRING COMMENT '学生ID',
	studentname STRING COMMENT '学生姓名',
	totalscore FLOAT COMMENT '试卷总分',
	classrank INT COMMENT '班级排名',
	problemnumber INT COMMENT '本次试卷试题号 eg. 1-20',
	studentscore FLOAT	COMMENT '试题得分'
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ',';
-- .csv文件本地路径如下
LOAD DATA LOCAL INPATH '/data/shujia/14304_test.csv'
INTO TABLE dw_tb_problem_score_v1;


-- 试卷号ID
DROP VIEW IF EXISTS view_examid;
CREATE VIEW IF NOT EXISTS view_examid AS
SELECT examid FROM dw_tb_problem_score_v1
LIMIT 1;
-- 考纲号ID
DROP VIEW IF EXISTS view_syllabusid;
CREATE VIEW IF NOT EXISTS view_syllabusid AS
SELECT DISTINCT syllabusid
FROM tb_exam AS t1 JOIN dw_tb_problem_score_v1 AS t2
ON t1.id = t2.examid;


-- 本次题目表1.0 本次考试出现的试题以及其分值
DROP TABLE IF EXISTS dw_tb_problem_v1;
CREATE external TABLE IF NOT EXISTS dw_tb_problem_v1(
	problemid STRING COMMENT '本次试题ID',
	problemnumber INT COMMENT '本次试题卷面编号',
	problemscore FLOAT COMMENT '本试题分值'
);
INSERT INTO TABLE dw_tb_problem_v1
SELECT id,questionno,score
FROM tb_exam_question AS t1 JOIN view_examid AS v1
ON  t1.examid = v1.examid;


--本次知识点表1.0 本次所遇到的知识点及对应的试题
DROP TABLE IF EXISTS dw_tb_point_v1;
CREATE external TABLE IF NOT EXISTS dw_tb_point_v1(
	pointid STRING COMMENT '知识点ID',
	problemid STRING COMMENT '试题ID'
);
INSERT INTO TABLE dw_tb_point_v1
SELECT pointid, problemid
FROM tb_exam_question_point AS t1 JOIN dw_tb_problem_v1 AS t2
ON  t1.examquestionid = t2.problemid;


--本次试题表2.0 添加试题对应知识点
DROP TABLE IF EXISTS dw_tb_problem_v2;
CREATE external TABLE IF NOT EXISTS dw_tb_problem_v2(
	problemid STRING COMMENT '本次试题ID',
	score FLOAT COMMENT '本试题分值',
	pointid STRING COMMENT '试题对应知识点ID'
);
INSERT INTO TABLE dw_tb_problem_v2
SELECT t1.problemid,score,pointid
FROM dw_tb_problem_v1 AS t1 JOIN dw_tb_point_v1 AS t2
ON t1.problemid = t2.problemid;


--本次试题表3.0 添加试题包含知识点占比，一题中有几个知识点
DROP TABLE IF EXISTS dw_tb_problem_v3;
CREATE external TABLE IF NOT EXISTS dw_tb_problem_v3(
	problemid STRING COMMENT '本次试题ID',
	score FLOAT COMMENT '本试题分值',
	pointid STRING COMMENT '试题对应知识点ID',
	proportion FLOAT COMMENT '试题对应 N个知识点，值为 1/N'
);
INSERT INTO TABLE dw_tb_problem_v3
SELECT t1.problemid,score,pointid,proportion
FROM dw_tb_problem_v2 AS t1 JOIN 
(SELECT problemid,1/COUNT(pointid) AS proportion
FROM dw_tb_problem_v2
GROUP BY problemid) t2
ON t1.problemid = t2.problemid;


--本次知识点表2.0
DROP TABLE IF EXISTS dw_tb_point_v2;
CREATE external TABLE IF NOT EXISTS dw_tb_point_v2(
	pointid STRING COMMENT '知识点ID',
	pointname STRING COMMENT '知识点名称',
	problemid STRING COMMENT '试题ID',
	parentid STRING COMMENT '父节点ID',
	topid STRING COMMENT '一级知识点ID',
	classhour FLOAT COMMENT '学时',
	frequency INT COMMENT '出现频率'
);
INSERT INTO TABLE dw_tb_point_v2
SELECT t2.pointid,pointname,t2.problemid,parentid,topid,classhour,frequency
FROM tb_syllabus_points AS t1 
JOIN view_syllabusid AS v1 ON t1.syllabusid = v1.syllabusid
JOIN dw_tb_point_v1 AS t2 ON t1.pointid = t2.pointid;


-- 本次知识点表3.0 计算知识点分值
DROP TABLE IF EXISTS dw_tb_point_v3;
CREATE external TABLE IF NOT EXISTS dw_tb_point_v3(
	pointid STRING COMMENT '知识点ID',
	pointname STRING COMMENT '知识点名称',
	pointscore FLOAT COMMENT '本次考试该知识点分值',
	problemid STRING COMMENT '试题ID',
	parentid STRING COMMENT '父节点ID',
	topid STRING COMMENT '一级知识点ID',
	classhour FLOAT COMMENT '学时',
	frequency INT COMMENT '出现频率',
	pointscore FLOAT COMMENT '知识点分值'
);
INSERT INTO TABLE dw_tb_point_v3
SELECT t1.pointid,t1.pointname,pointscore,t1.problemid,parentid,topid,classhour,frequency
FROM dw_tb_point_v2 AS t1
JOIN (SELECT pointid,SUM(score*proportion) AS pointscore
FROM dw_tb_problem_v3
GROUP BY pointid) AS t2 
ON t1.pointid = t2.pointid;

DROP TABLE IF EXISTS dw_tb_problem_score_v2;
CREATE external TABLE IF NOT EXISTS dw_tb_problem_score_v2(
	examid STRING COMMENT '试卷ID',
	studentid STRING COMMENT '学生ID',
	studentname STRING COMMENT '学生姓名',
	totalscore FLOAT COMMENT '试卷总分',
	classrank INT COMMENT '班级排名',
	problemid STRING COMMENT '试题ID',
	problemnumber INT COMMENT '本次试卷试题号 eg. 1-20',
	problemscore FLOAT	COMMENT '试题得分',
	score FLOAT COMMENT '试题总分',
	problemrate FLOAT COMMENT '试题得分比率'
);