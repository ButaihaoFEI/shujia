USE shujia;


-- 插入csv 数据到表中
DROP TABLE IF EXISTS dw_tb_stu_problem_score_v1;
CREATE external TABLE IF NOT EXISTS dw_tb_stu_problem_score_v1(
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
INTO TABLE dw_tb_stu_problem_score_v1;


-- 试卷号ID
DROP VIEW IF EXISTS view_examid;
CREATE VIEW IF NOT EXISTS view_examid AS
SELECT examid FROM dw_tb_stu_problem_score_v1
LIMIT 1;
-- 考纲号ID
DROP VIEW IF EXISTS view_syllabusid;
CREATE VIEW IF NOT EXISTS view_syllabusid AS
SELECT DISTINCT syllabusid
FROM tb_exam AS t1 JOIN dw_tb_stu_problem_score_v1 AS t2
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

--本次学生题目得分情况表2.0 增加题目ID，题目分值，题目得分率，按总分排名，题目顺序排序
DROP TABLE IF EXISTS dw_tb_stu_problem_score_v2;
CREATE external TABLE IF NOT EXISTS dw_tb_stu_problem_score_v2(
	studentid STRING COMMENT '学生ID',
	studentname STRING COMMENT '学生姓名',
	totalscore FLOAT COMMENT '试卷总分',
	classrank INT COMMENT '班级排名',
	problemid STRING COMMENT '试题ID',
	problemnumber INT COMMENT '本次试卷试题号 eg. 1-20',
	studentscore FLOAT	COMMENT '试题得分',
	problemscore FLOAT COMMENT '试题分值',
	problemrate FLOAT COMMENT '试题得分率'
);
INSERT INTO TABLE dw_tb_stu_problem_score_v2
SELECT t1.studentid,t1.studentname,t1.totalscore,t1.classrank,t2.problemid,t1.problemnumber,t1.studentscore,t2.problemscore,(t1.studentscore/t2.problemscore) AS problemrate
FROM dw_tb_stu_problem_score_v1 AS t1
JOIN dw_tb_problem_v1 AS t2
ON t1.problemnumber = t2.problemnumber
ORDER BY t1.classrank ASC, t1.problemnumber ASC;


--本次试题知识点关系表 本次所遇到的试题及对应的知识点
DROP TABLE IF EXISTS dw_tb_question_point_v1;
CREATE external TABLE IF NOT EXISTS dw_tb_question_point_v1(
	problemid STRING COMMENT '试题ID',
	pointid STRING COMMENT '知识点ID'
);
INSERT INTO TABLE dw_tb_question_point_v1
SELECT problemid,pointid
FROM tb_exam_question_point AS t1 JOIN dw_tb_problem_v1 AS t2
ON  t1.examquestionid = t2.problemid;


--本次试题知识点关系表2.0 添加试题包含知识点占比，一题中有几个知识点
DROP TABLE IF EXISTS dw_tb_question_point_v2;
CREATE external TABLE IF NOT EXISTS dw_tb_question_point_v2(
	problemid STRING COMMENT '试题ID',
	pointid STRING COMMENT '知识点ID',
	proportion FLOAT COMMENT '试题对应 N个知识点，值为 1/N'
);
INSERT INTO TABLE dw_tb_question_point_v2
SELECT t1.problemid,t1.pointid,proportion
FROM dw_tb_question_point_v1 AS t1 JOIN 
(SELECT problemid,1/COUNT(pointid) AS proportion
FROM dw_tb_question_point_v1
GROUP BY problemid) t2
ON t1.problemid = t2.problemid;


--本次知识点表1.0
DROP TABLE IF EXISTS dw_tb_point_v1;
CREATE external TABLE IF NOT EXISTS dw_tb_point_v1(
	pointid STRING COMMENT '知识点ID',
	pointname STRING COMMENT '知识点名称',
	parentid STRING COMMENT '父节点ID',
	topid STRING COMMENT '一级知识点ID',
	classhour FLOAT COMMENT '学时',
	frequency INT COMMENT '出现频率'
);
INSERT INTO TABLE dw_tb_point_v1
SELECT t2.pointid,pointname,parentid,topid,classhour,frequency
FROM tb_syllabus_points AS t1 
JOIN view_syllabusid AS v1 ON t1.syllabusid = v1.syllabusid
JOIN dw_tb_question_point AS t2 ON t1.pointid = t2.pointid;


-- 本次知识点表2.0 计算知识点分值
DROP TABLE IF EXISTS dw_tb_point_v2;
CREATE external TABLE IF NOT EXISTS dw_tb_point_v2(
	pointid STRING COMMENT '知识点ID',
	pointname STRING COMMENT '知识点名称',
	parentid STRING COMMENT '父节点ID',
	topid STRING COMMENT '一级知识点ID',
	classhour FLOAT COMMENT '学时',
	frequency INT COMMENT '出现频率',
	pointscore FLOAT COMMENT '知识点分值'
);
INSERT INTO TABLE dw_tb_point_v2
SELECT t4.pointid,t4.pointname,t4.parentid,t4.topid,t4.classhour,t4.frequency,t3.pointscore
FROM 
(SELECT t2.pointid, SUM(problemscore*proportion) AS pointscore
FROM dw_tb_problem_v1 AS t1
JOIN dw_tb_question_point_v2 AS t2
ON t1.problemid = t2.problemid
GROUP BY t2.pointid) AS t3
JOIN dw_tb_point_v1 AS t4
ON t3.pointid = t4.pointid;


--本次学生知识点得分情况表
--正在进行多维钻取
SELECT t4.studentid,t4.studentname,t3.pointid,t5.pointname,t3.studentpointscore,t5.pointscore,(t3.studentpointscore/t5.pointscore) AS pointrate
FROM
(SELECT t1.studentid,t2.pointid,SUM(t1.problemscore*t2.proportion) AS studentpointscore
FROM dw_tb_stu_problem_score_v2 AS t1
JOIN dw_tb_question_point_v2 AS t2
ON t1.problemid = t2.problemid
GROUP BY t2.pointid,t1.studentid
GROUPING SETS((t2.pointid,t1.studentid),t2.pointid,t1.studentid,())
) AS t3
JOIN dw_tb_stu_problem_score_v2 AS t4
ON t3.studentid = t4.studentid
JOIN dw_tb_point_v2 AS t5
ON t3.pointid = t5.pointid

