USE shujia;
--map join open
SET hive.auto.convert.join = TRUE;

--local mode
SET hvie.exec.mode.local.auto = TRUE;

-- 插入csv 数据到表中
DROP TABLE IF EXISTS dw_tb_stu_problem_score_v1;
CREATE TABLE IF NOT EXISTS dw_tb_stu_problem_score_v1(
examid STRING COMMENT '试卷ID',
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
totalscore FLOAT COMMENT '试卷总分',
classrank INT COMMENT '班级排名',
problemnumber INT COMMENT '本次试卷试题号 eg. 1-20',
studentscore FLOAT	COMMENT '试题得分'
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_problem_score_v1';
-- .csv文件本地路径如下
LOAD DATA LOCAL INPATH '/data/shujia/14304_test.csv'
INTO TABLE dw_tb_stu_problem_score_v1;


-- 试卷号ID
DROP TABLE IF EXISTS dw_variable_examid;
CREATE TABLE IF NOT EXISTS dw_variable_examid AS
SELECT examid FROM dw_tb_stu_problem_score_v1
LIMIT 1;
-- 考纲号ID
DROP TABLE IF EXISTS dw_variable_syllabusid;
CREATE TABLE IF NOT EXISTS dw_variable_syllabusid AS
SELECT DISTINCT syllabusid
FROM tb_exam AS t1 JOIN dw_tb_stu_problem_score_v1 AS t2
ON t1.id = t2.examid;
-- 学校号班级号
DROP TABLE IF EXISTS dw_variable_schoolid_classesid;
CREATE TABLE IF NOT EXISTS dw_variable_schoolid_classesid AS
SELECT DISTINCT schoolid,classesid
FROM tb_student AS t1 JOIN
(SELECT studentid FROM dw_tb_stu_problem_score_v1
LIMIT 1) AS t2
ON t1.studentid = t2.studentid;



--学生名单表
DROP TABLE IF EXISTS dw_tb_stu_v1;
CREATE TABLE IF NOT EXISTS dw_tb_stu_v1
(
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
totalscore FLOAT COMMENT '试卷总分',
classrank INT COMMENT '班级排名'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_v1';
INSERT INTO TABLE dw_tb_stu_v1
SELECT DISTINCT studentid,studentname,totalscore,classrank
FROM dw_tb_stu_problem_score_v1
ORDER BY classrank ASC; 


-- 本次题目表1.0 本次考试出现的试题以及其分值
DROP TABLE IF EXISTS dw_tb_problem_v1;
CREATE TABLE IF NOT EXISTS dw_tb_problem_v1(
problemid STRING COMMENT '本次试题ID',
problemnumber INT COMMENT '本次试题卷面编号',
problemscore FLOAT COMMENT '本试题分值'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_problem_v1';
INSERT INTO TABLE dw_tb_problem_v1
SELECT id,questionno,score
FROM tb_exam_question AS t1 JOIN dw_variable_examid AS v1
ON  t1.examid = v1.examid;


--本次学生题目得分情况表2.0 增加题目ID，题目分值，题目得分率，按总分排名，题目顺序排序
DROP TABLE IF EXISTS dw_tb_stu_problem_score_v2;
CREATE  TABLE IF NOT EXISTS dw_tb_stu_problem_score_v2(
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
totalscore FLOAT COMMENT '试卷总分',
classrank INT COMMENT '班级排名',
problemid STRING COMMENT '试题ID',
problemnumber INT COMMENT '本次试卷试题号 eg. 1-20',
studentscore FLOAT	COMMENT '试题得分',
problemscore FLOAT COMMENT '试题分值',
problemrate FLOAT COMMENT '试题得分率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_problem_score_v2';
INSERT INTO TABLE dw_tb_stu_problem_score_v2
SELECT t1.studentid,t1.studentname,t1.totalscore,t1.classrank,t2.problemid,t1.problemnumber,t1.studentscore,t2.problemscore,(t1.studentscore/t2.problemscore) AS problemrate
FROM dw_tb_stu_problem_score_v1 AS t1
JOIN dw_tb_problem_v1 AS t2
ON t1.problemnumber = t2.problemnumber
ORDER BY t1.classrank ASC, t1.problemnumber ASC;


--本次试题知识点关系表 本次所遇到的试题及对应的知识点
DROP TABLE IF EXISTS dw_tb_problem_point_v1;
CREATE TABLE IF NOT EXISTS dw_tb_problem_point_v1(
problemid STRING COMMENT '试题ID',
pointid STRING COMMENT '知识点ID'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_problem_point_v1';
INSERT INTO TABLE dw_tb_problem_point_v1
SELECT problemid,pointid
FROM tb_exam_question_point AS t1 JOIN dw_tb_problem_v1 AS t2
ON  t1.examquestionid = t2.problemid;


--本次试题知识点关系表2.0 添加试题包含知识点占比，一题中有几个知识点
DROP TABLE IF EXISTS dw_tb_problem_point_v2;
CREATE TABLE IF NOT EXISTS dw_tb_problem_point_v2(
problemid STRING COMMENT '试题ID',
pointid STRING COMMENT '知识点ID',
proportion FLOAT COMMENT '试题对应 N个知识点，值为 1/N'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_problem_point_v2';
INSERT INTO TABLE dw_tb_problem_point_v2
SELECT t1.problemid,t1.pointid,proportion
FROM dw_tb_problem_point_v1 AS t1 JOIN 
(SELECT problemid,1/COUNT(pointid) AS proportion
FROM dw_tb_problem_point_v1
GROUP BY problemid) t2
ON t1.problemid = t2.problemid;


--本次叶知识点表1.0
DROP TABLE IF EXISTS dw_tb_point_v1;
CREATE TABLE IF NOT EXISTS dw_tb_point_v1(
pointid STRING COMMENT '知识点ID',
pointname STRING COMMENT '知识点名称',
parentid STRING COMMENT '父节点ID',
topid STRING COMMENT '一级知识点ID',
classhour FLOAT COMMENT '学时',
frequency INT COMMENT '出现频率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_point_v1';
INSERT INTO TABLE dw_tb_point_v1
SELECT t2.pointid,pointname,parentid,topid,classhour,replace(replace(replace(frequency,2,10),3,50),4,250)
FROM tb_syllabus_points AS t1 
JOIN dw_variable_syllabusid AS v1 ON t1.syllabusid = v1.syllabusid
JOIN dw_tb_problem_point_v2 AS t2 ON t1.pointid = t2.pointid;


-- 本次叶知识点表2.0 计算知识点分值
DROP TABLE IF EXISTS dw_tb_point_v2;
CREATE TABLE IF NOT EXISTS dw_tb_point_v2(
pointid STRING COMMENT '知识点ID',
pointname STRING COMMENT '知识点名称',
parentid STRING COMMENT '父节点ID',
topid STRING COMMENT '一级知识点ID',
classhour FLOAT COMMENT '学时',
frequency INT COMMENT '出现频率',
pointscore FLOAT COMMENT '知识点分值'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_point_v2';
INSERT INTO TABLE dw_tb_point_v2
SELECT t4.pointid,t4.pointname,t4.parentid,t4.topid,t4.classhour,t4.frequency,t3.pointscore
FROM dw_tb_point_v1 AS t4
JOIN (SELECT t2.pointid, SUM(problemscore*proportion) AS pointscore
FROM dw_tb_problem_v1 AS t1
JOIN dw_tb_problem_point_v2 AS t2
ON t1.problemid = t2.problemid
GROUP BY t2.pointid) AS t3
ON t3.pointid = t4.pointid;

--一级知识点表
DROP TABLE IF EXISTS dw_tb_first_class_point_v1;
CREATE TABLE IF NOT EXISTS dw_tb_first_class_point_v1(
pointid STRING COMMENT '知识点ID',
pointname STRING COMMENT '知识点名称',
pointscore FLOAT COMMENT '知识点分值'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_first_class_point_v1';
INSERT INTO TABLE dw_tb_first_class_point_v1
SELECT t2.pointid,pointname,pointscore
FROM tb_syllabus_points AS t1
JOIN
(SELECT topid AS pointid,SUM(pointscore) AS pointscore
FROM dw_tb_point_v2
GROUP BY topid) AS t2
ON t1.pointid = t2.pointid;

--一级知识点得分表
SELECT t4.topid,pointname,studentpointscore,pointscore,(studentpointscore/pointscore) AS pointrate
FROM
dw_tb_first_class_point_v1 AS t3
JOIN
(
SELECT topid,SUM(studentpointscore) AS studentpointscore
FROM
(SELECT t1.pointid,topid,studentpointscore,pointscore
FROM dw_tb_point_v2 AS t2
JOIN
(SELECT pointid,AVG(studentpointscore) AS studentpointscore
FROM dw_tb_stu_point_score_v1
GROUP BY pointid) AS t1
ON t1.pointid = t2.pointid)
GROUP BY topid) AS t4
ON t3.pointid=t4.topid;



--本次试题题型关系表1.0
DROP TABLE IF EXISTS dw_tb_problem_questiontype_v1;
CREATE TABLE IF NOT EXISTS dw_tb_problem_questiontype_v1(
problemid STRING COMMENT '试题ID',
questiontypeid STRING COMMENT '题型ID'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_problem_questiontype_v1';
INSERT INTO TABLE dw_tb_problem_questiontype_v1
SELECT  t1.problemid,t2.questiontypeid
FROM dw_tb_problem_v1 AS t1
JOIN tb_exam_questiontype AS t2
ON t1.problemid = t2.examquestionid;


--本次试题题型关系表2.0 添加试题包含题型占比，一题中有几个题型
DROP TABLE IF EXISTS dw_tb_problem_questiontype_v2;
CREATE TABLE IF NOT EXISTS dw_tb_problem_questiontype_v2(
problemid STRING COMMENT '试题ID',
questiontypeid STRING COMMENT '题型ID',
proportion FLOAT COMMENT '试题对应 N个题型，值为 1/N'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_problem_questiontype_v2';
INSERT INTO TABLE dw_tb_problem_questiontype_v2
SELECT t1.problemid,t1.questiontypeid,proportion
FROM dw_tb_problem_questiontype_v1 AS t1 JOIN 
(SELECT problemid,1/COUNT(questiontypeid) AS proportion
FROM dw_tb_problem_questiontype_v1
GROUP BY problemid) t2
ON t1.problemid = t2.problemid;


--本次题型表1.0
DROP TABLE IF EXISTS dw_tb_questiontype_v1;
CREATE TABLE IF NOT EXISTS dw_tb_questiontype_v1(
questiontypeid STRING COMMENT '题型ID',
questiontypename STRING COMMENT '题型名称',
parentid STRING COMMENT '父节点ID',
topid STRING COMMENT '一级知识点ID',
frequency INT COMMENT '出现频率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_questiontype_v1';
INSERT INTO TABLE dw_tb_questiontype_v1
SELECT t1.questiontypeid,questiontype_name,parent_id,top_id,replace(replace(replace(exam_frequency,2,10),3,50),4,250)
FROM dw_tb_problem_questiontype_v2 AS t1
JOIN tb_exam_questiontype_analysis AS t2
ON t1.questiontypeid = t2.id;


--本次题型表2.0
DROP TABLE IF EXISTS dw_tb_questiontype_v2;
CREATE TABLE IF NOT EXISTS dw_tb_questiontype_v2(
questiontypeid STRING COMMENT '题型ID',
questiontypename STRING COMMENT '题型名称',
parentid STRING COMMENT '父节点ID',
topid STRING COMMENT '一级知识点ID',
frequency INT COMMENT '出现频率',
questiontypescore FLOAT COMMENT '题型分值'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_questiontype_v2';
INSERT INTO TABLE dw_tb_questiontype_v2
SELECT t4.questiontypeid,questiontypename,parentid,topid,frequency,questiontypescore
FROM dw_tb_questiontype_v1 AS t4
JOIN
(SELECT t2.questiontypeid, SUM(problemscore*proportion) AS questiontypescore
FROM dw_tb_problem_v1 AS t1
JOIN dw_tb_problem_questiontype_v2 AS t2
ON t1.problemid = t2.problemid
GROUP BY t2.questiontypeid) AS t3
ON t4.questiontypeid = t3.questiontypeid;


--本次学生知识点得分情况表
--正在进行多维钻取
DROP TABLE IF EXISTS dw_tb_stu_point_score_v1;
CREATE TABLE IF NOT EXISTS dw_tb_stu_point_score_v1(
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
pointid STRING COMMENT '知识点ID',
pointname STRING COMMENT '知识点名称',
studentpointscore FLOAT	COMMENT '学生知识点得分',
pointscore FLOAT COMMENT '知识点分值',
pointrate FLOAT COMMENT '知识点得分率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_point_score_v1';
INSERT INTO TABLE dw_tb_stu_point_score_v1
SELECT t4.studentid,t4.studentname,t3.pointid,t5.pointname,t3.studentpointscore,t5.pointscore,(t3.studentpointscore/t5.pointscore) AS pointrate
FROM dw_tb_point_v2 AS t5
JOIN 
(SELECT t1.studentid,t2.pointid,SUM(t1.studentscore*t2.proportion) AS studentpointscore
FROM dw_tb_stu_problem_score_v2 AS t1
JOIN dw_tb_problem_point_v2 AS t2
ON t1.problemid = t2.problemid
GROUP BY t1.studentid,t2.pointid
) AS t3
ON t3.pointid = t5.pointid
JOIN dw_tb_stu_v1 AS t4
ON t3.studentid = t4.studentid;


--学生题型得分情况表
DROP TABLE IF EXISTS dw_tb_stu_questiontype_score_v1;
CREATE TABLE IF NOT EXISTS dw_tb_stu_questiontype_score_v1(
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
questiontypeid STRING COMMENT '知识点ID',
questiontypename STRING COMMENT '知识点名称',
studentquestiontypescore FLOAT	COMMENT '学生知识点得分',
questiontypescore FLOAT COMMENT '知识点分值',
questiontyperate FLOAT COMMENT '知识点得分率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_questiontype_score_v1';
INSERT INTO TABLE dw_tb_stu_questiontype_score_v1
SELECT t4.studentid,t4.studentname,t3.questiontypeid,t5.questiontypename,t3.studentquestiontypescore,t5.questiontypescore,(t3.studentquestiontypescore/t5.questiontypescore) AS questiontyperate
FROM dw_tb_questiontype_v2 AS t5 
JOIN
(SELECT t1.studentid,t2.questiontypeid,SUM(t1.studentscore*t2.proportion) AS studentquestiontypescore
FROM dw_tb_problem_questiontype_v2 AS t2
JOIN dw_tb_stu_problem_score_v2 AS t1
ON t1.problemid = t2.problemid
GROUP BY t1.studentid,t2.questiontypeid
) AS t3
ON t3.questiontypeid = t5.questiontypeid
JOIN dw_tb_stu_v1 AS t4
ON t3.studentid = t4.studentid; 


--得分区间表，区间从excel中设立
DROP TABLE IF EXISTS dw_tb_scoreinterval;
CREATE TABLE IF NOT EXISTS dw_tb_scoreinterval(
totalscore int COMMENT '得分区间',
interval_min int COMMENT '区间最小值',
interval_max int COMMENT '区间最大值'
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
LOCATION '/user/hadoop/shujia/dw/dw_tb_scoreinterval';
LOAD DATA LOCAL INPATH '/data/shujia/dw_tb_scoreinterval.csv'
INTO TABLE dw_tb_scoreinterval;


--知识点得分区间1.0
DROP TABLE IF EXISTS dw_tb_scoreinterval_point_v1;
CREATE TABLE IF NOT EXISTS dw_tb_scoreinterval_point_v1(
totalscore int COMMENT '得分区间',
student int COMMENT '该区间内学生人数',
pointid STRING,
pointrate_avg FLOAT COMMENT '该区间内学生该知识点平均得分率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_scoreinterval_point_v1';
INSERT INTO TABLE dw_tb_scoreinterval_point_v1
SELECT t4.totalscore,COUNT(t3.studentid),t3.pointid,IF(COUNT(t3.studentid) >1,AVG(t3.pointrate),t4.totalscore/150)
FROM
dw_tb_scoreinterval AS t4
JOIN
(SELECT t2.studentid,t2.studentname,totalscore,pointid,pointname,pointrate
FROM dw_tb_stu_v1 AS t1
JOIN dw_tb_stu_point_score_v1 AS t2
ON t1.studentid = t2.studentid) AS t3
WHERE (t3.totalscore >= t4.interval_min) AND (t3.totalscore <= t4.interval_max)
GROUP BY t4.totalscore,t3.pointid;



--推荐知识点指标表1.0
DROP TABLE IF EXISTS dw_tb_stu_recommand_point_v1;
CREATE TABLE IF NOT EXISTS dw_tb_stu_recommand_point_v1(
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
totalscore INT COMMENT '学生总分',
pointid STRING COMMENT '学生欠缺知识点ID',
pointname STRING COMMENT '知识点名称',
studentpointrate FLOAT COMMENT '学生该知识点得分率',
scoreintervalpointrate FLOAT COMMENT'学生所在区间知识点得分率',
difference FLOAT COMMENT'学生所在区间该知识点得分率与学生该知识点得分率差值'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_recommand_point_v1';
INSERT INTO TABLE dw_tb_stu_recommand_point_v1
SELECT t3.studentid,t3.studentname,t3.totalscore,t3.pointid,t3.pointname,t3.studentpointrate,t4.pointrate_avg AS scoreintervalpointrate, ROUND(t4.pointrate_avg - t3.studentpointrate,2) AS difference
FROM(SELECT t2.studentid,t2.studentname,t1.totalscore,t2.pointid,t2.pointname,t2.pointrate AS studentpointrate
FROM dw_tb_stu_v1 AS t1
JOIN dw_tb_stu_point_score_v1 AS t2
ON t1.studentid=t2.studentid
ORDER BY t1.totalscore DESC) AS t3
LEFT JOIN dw_tb_scoreinterval_point_v1 AS t4
ON t3.pointid = t4.pointid
WHERE t3.totalscore = t4.totalscore AND t3.studentpointrate < t4.pointrate_avg 
ORDER BY t3.totalscore DESC,t3.studentname,difference DESC;



--推荐知识点指标表2.0
DROP TABLE IF EXISTS dw_tb_stu_recommand_point_v2;
CREATE TABLE IF NOT EXISTS dw_tb_stu_recommand_point_v2(
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
totalscore INT COMMENT '学生总分',
pointid STRING COMMENT '学生欠缺知识点ID',
pointname STRING COMMENT '知识点名称',
studentpointrate FLOAT COMMENT '学生该知识点得分率',
scoreintervalpointrate FLOAT COMMENT'学生所在区间知识点得分率',
difference FLOAT COMMENT'学生所在区间该知识点得分率与学生该知识点得分率差值',
t_value FLOAT COMMENT '学时',
differencescore FLOAT COMMENT '分值差距',
frequency INT COMMENT '频率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_recommand_point_v2';
INSERT INTO TABLE dw_tb_stu_recommand_point_v2
SELECT studentid,studentname,totalscore,t1.pointid,t1.pointname,studentpointrate,scoreintervalpointrate,difference,ROUND((((1/3) * POWER(scoreintervalpointrate,3) - (1/2) * POWER(scoreintervalpointrate,2) + (1/4) * scoreintervalpointrate) - ((1/3) * POWER(studentpointrate,3) - (1/2) * POWER(studentpointrate,2) + (1/4) * studentpointrate)) *12 * classhour * 2,0)/2 +0.5 AS t, difference * pointscore AS differencescore, frequency
FROM dw_tb_point_v2 AS t1
JOIN dw_tb_stu_recommand_point_v1 AS t2
ON t1.pointid = t2.pointid
ORDER BY totalscore DESC,studentname,differencescore*frequency/t DESC;



--题型得分区间1.0
DROP TABLE IF EXISTS dw_tb_scoreinterval_questiontype_v1;
CREATE TABLE IF NOT EXISTS dw_tb_scoreinterval_questiontype_v1(
totalscore int COMMENT '得分区间',
student int COMMENT '该区间内学生人数',
questiontypeid STRING,
questiontyperate_avg FLOAT COMMENT '该区间内学生该题型平均得分率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_scoreinterval_questiontype_v1';
INSERT INTO TABLE dw_tb_scoreinterval_questiontype_v1
SELECT t4.totalscore,COUNT(t3.studentid),t3.questiontypeid,IF(COUNT(t3.studentid) >1,AVG(t3.questiontyperate),t4.totalscore/150)
FROM
dw_tb_scoreinterval AS t4
JOIN
(SELECT t2.studentid,t2.studentname,totalscore,questiontypeid,questiontypename,questiontyperate
FROM dw_tb_stu_v1 AS t1
JOIN dw_tb_stu_questiontype_score_v1 AS t2
ON t1.studentid = t2.studentid) AS t3
WHERE (t3.totalscore >= t4.interval_min) AND (t3.totalscore <= t4.interval_max)
GROUP BY t4.totalscore,t3.questiontypeid;



--推荐题型指标表1.0
DROP TABLE IF EXISTS dw_tb_stu_recommand_questiontype_v1;
CREATE TABLE IF NOT EXISTS dw_tb_stu_recommand_questiontype_v1(
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
totalscore INT COMMENT '学生总分',
questiontypeid STRING COMMENT '学生欠缺题型ID',
questiontypename STRING COMMENT '题型名称',
studentquestiontyperate FLOAT COMMENT '学生该题型得分率',
scoreintervalquestiontyperate FLOAT COMMENT'学生所在区间题型得分率',
difference FLOAT COMMENT'学生所在区间该题型得分率与学生该题型得分率差值'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_recommand_questiontype_v1';
INSERT INTO TABLE dw_tb_stu_recommand_questiontype_v1
SELECT t3.studentid,t3.studentname,t3.totalscore,t3.questiontypeid,t3.questiontypename,t3.studentquestiontyperate,t4.questiontyperate_avg AS scoreintervalquestiontyperate, ROUND(t4.questiontyperate_avg - t3.studentquestiontyperate,2) AS difference
FROM(SELECT t2.studentid,t2.studentname,t1.totalscore,t2.questiontypeid,t2.questiontypename,t2.questiontyperate AS studentquestiontyperate
FROM dw_tb_stu_v1 AS t1
JOIN dw_tb_stu_questiontype_score_v1 AS t2
ON t1.studentid=t2.studentid
ORDER BY t1.totalscore DESC) AS t3
LEFT JOIN dw_tb_scoreinterval_questiontype_v1 AS t4
ON t3.questiontypeid = t4.questiontypeid
WHERE t3.totalscore = t4.totalscore AND t3.studentquestiontyperate < t4.questiontyperate_avg 
ORDER BY t3.totalscore DESC,t3.studentname,difference DESC;


--推荐知识点指标表2.0
DROP TABLE IF EXISTS dw_tb_stu_recommand_questiontype_v2;
CREATE TABLE IF NOT EXISTS dw_tb_stu_recommand_questiontype_v2(
studentid STRING COMMENT '学生ID',
studentname STRING COMMENT '学生姓名',
totalscore INT COMMENT '学生总分',
questiontypeid STRING COMMENT '学生欠缺题型ID',
questiontypename STRING COMMENT '题型名称',
studentquestiontyperate FLOAT COMMENT '学生该题型得分率',
scoreintervalquestiontyperate FLOAT COMMENT'学生所在区间题型得分率',
difference FLOAT COMMENT'学生所在区间该题型得分率与学生该题型得分率差值',
differencescore FLOAT COMMENT '题型分值差距',
frequency INT COMMENT '频率'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_stu_recommand_questiontype_v2';
INSERT INTO TABLE dw_tb_stu_recommand_questiontype_v2
SELECT studentid,studentname,totalscore,t1.questiontypeid,t1.questiontypename,studentquestiontyperate,scoreintervalquestiontyperate,difference, difference * questiontypescore AS differencescore, frequency
FROM dw_tb_questiontype_v2 AS t1
JOIN dw_tb_stu_recommand_questiontype_v1 AS t2
ON t1.questiontypeid = t2.questiontypeid
ORDER BY totalscore DESC,studentname,differencescore*frequency DESC;


--划分简单题，非简单题
--计算每道题的班级平均分
--平均分大于0.7为简单题，标签为1,非简单题为0
--题目表2.0
DROP TABLE IF EXISTS dw_tb_problem_v2;
CREATE TABLE IF NOT EXISTS dw_tb_problem_v2(
problemid STRING COMMENT '本次试题ID',
problemnumber INT COMMENT '本次试题卷面编号',
problemscore FLOAT COMMENT '本试题分值',
studentscorerate_avg FLOAT COMMENT '该题班级平均分',
problemtag INT COMMENT '简单题 - 1，非简单题 - 0 标签'
)
LOCATION '/user/hadoop/shujia/dw/dw_tb_problem_v2';
INSERT INTO TABLE dw_tb_problem_v2
SELECT t2.problemid,problemnumber,problemscore,ROUND(studentscorerate_avg,2),IF(studentscorerate_avg>0.7,1,0)
FROM
(SELECT problemid,AVG(problemrate) AS studentscorerate_avg
FROM dw_tb_stu_problem_score_v2
GROUP BY problemid) AS t1
JOIN dw_tb_problem_v1 AS t2
ON t1.problemid = t2.problemid
ORDER BY problemnumber ASC;


--给学生打上相应标签（发挥失常，能力有限）

DROP TABLE IF EXISTS dw_tmp_student_score_tag;
CREATE TABLE IF NOT EXISTS dw_tmp_student_score_tag(
studentid STRING COMMENT '学生ID',
problemtag INT COMMENT '题目标签 简单题 - 1，非简单题 - 0 标签',
studentscore FLOAT COMMENT '该标签学生得分',
studentscore_avg FLOAT COMMENT '该标签班级平均分',
studentscore_std FLOAT COMMENT '该标签班级得分标准差'
)
LOCATION '/user/hadoop/shujia/dw/dw_tmp_student_score_tag';
INSERT INTO TABLE dw_tmp_student_score_tag
SELECT t4.studentid,t4.problemtag,t4.studentscore,t5.studentscore_avg,t5.studentscore_std
FROM 
(
--班级平均分，标准差
SELECT problemtag,SUM(problemscore * studentscorerate_avg) AS studentscore_avg, STDDEV(problemscore * studentscorerate_avg) AS studentscore_std
FROM dw_tb_problem_v2 
GROUP BY problemtag) AS t5
JOIN
(
--学生简单题，非简单题得分
SELECT t3.studentid,t3.problemtag,SUM(studentscore) AS studentscore
FROM(
SELECT t2.studentid,t2.studentname,t1.problemnumber,t2.studentscore,t1.problemtag
FROM dw_tb_problem_v2 AS t1
JOIN dw_tb_stu_problem_score_v2 AS t2
ON t1.problemnumber = t2.problemnumber) AS t3
GROUP BY studentid,problemtag
DISTRIBUTE BY studentid SORT BY studentid,problemtag ) AS t4
ON t4.problemtag = t5.problemtag;



-- 插入知识点推荐表
--INSERT INTO TABLE tb_exam_student_points_scheme_detail
SELECT regexp_replace(reflect("java.util.UUID","randomUUID"),"-",""),examid,studentid,pointid,INT((scoreintervalpointrate-studentpointrate) * 100),t_value,INT(studentpointrate * 100),INT(scoreintervalpointrate * 100),1
FROM dw_variable_examid  
JOIN dw_tb_stu_recommand_point_v2;

-- 插入题型推荐
--INSERT INTO TABLE tb_exam_student_questiontype_recommended_strategy
SELECT regexp_replace(reflect("java.util.UUID","randomUUID"),"-",""),examid,studentid,questiontypeid,INT(studentquestiontyperate * 100)
from_unixtime(unix_timestamp(),'yyyy-MM-dd HH:mm:ss')


-- 学生考试信息汇总
-- INSERT INTO TABLE tb_exam_student
SELECT regexp_replace(reflect("java.util.UUID","randomUUID"),"-",""),studentid,examid,totalscore,,classrank,classrank,
FROM dw_variable_examid
JOIN dw_tb_stu_problem_score_v2

SELECT classesranking,totalranking FROM tb_exam_student
LIMIT 50;

-- 本次出现的一级知识点
-- 如果数据库有这次考试记录则更新知识点信息，否则新增这次考试记录 
-- 1分40秒 特别慢，没有外键的连接，效率低
-- INSERT INTO TABLE tb_exam_classes_point_group
SELECT regexp_replace(reflect("java.util.UUID","randomUUID"),"-","") AS id,examid,schoolid,topid
FROM dw_variable_schoolid_classesid AS t1
JOIN
(SELECT examid,topid
FROM dw_variable_examid AS t2
JOIN (SELECT DISTINCT topid FROM dw_tb_point_v2) AS t3) AS t4;


-- 本张试卷下班级得分标准差
-- INSERT INTO TABLE tb_exam_classes_totalscore_std
SELECT regexp_replace(reflect("java.util.UUID","randomUUID"),"-","") AS id,examid,schoolid,classesid,std
FROM dw_variable_schoolid_classesid AS t1
JOIN 
(SELECT examid,std 
FROM dw_variable_examid AS t3
JOIN (SELECT STDDEV(totalscore) AS std FROM dw_tb_stu_v1) AS t4 ) AS t2;

-- 试题平均值
-- INSERT INTO TABLE tb_exam_question_rate
SELECT regexp_replace(reflect("java.util.UUID","randomUUID"),"-","") AS id,examid,problemid,(studentscorerate_avg * 100) AS scorerate
FROM dw_variable_examid
JOIN dw_tb_problem_v2




