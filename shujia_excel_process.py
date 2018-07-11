# coding: utf-8

import pandas as pd

df_name = list(pd.read_csv('/data/shujia/36568.csv',nrows = 0))[4:]

df = pd.read_csv('/data/shujia/36568.csv',skiprows = 1)

# 命名列名
df.columns = ['examid', 'studentid','studentnumber','studentname'] + df_name

# 删除学号列
df = df.drop('studentnumber',1)

# 计算总分，增加总分列
df['totalscore'] = df.iloc[:,3:].apply(lambda x: x.sum(), axis=1) 

# 总分排序
df = df.sort_values(by = 'totalscore',ascending=False)

# 增加排名列
df['classrank'] = df['totalscore'].rank(method='max',ascending=False)

# 多层索引，聚合各题分数
df_1 = df.set_index(['examid','studentid','studentname','totalscore','classrank']).stack()


df_1.to_csv('/data/shujia/36568.csv')

