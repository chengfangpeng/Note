## 概述
RecyclerView中有许多神奇的特性，比如局部刷新，它不仅可以针对某个item进行刷新，也可以针对item中的某些数据进行刷新。这对我们页面的页面渲染带来了很大的提升。那么RecyclerView是怎么通过对新旧数据的对比来做到局部刷新的？更进一步，对比新旧数据的这个Diff算法又是什么的样子的。下面将会从这两个部分来展开讨论。

## RecyclerView的局部刷新



## Diff算法
在上面使用RecyclerView做局部刷新的时候，使用了一个DiffUtil工具类。那么这个工具类是基于什么样的算法实现的？
要讲明白这个问题需先介绍一些概念

#### 概念解释

- Myers Diff算法  
 DiffUtil这个工具类使用的Diff算法来自于Eugene W. Myers在1986年发表的一篇算法[论文](http://xmailserver.org/diff2.pdf)

 - 最短编辑脚本(SES Shortest Edit Script)

 - 最长公共子序列(LCS Longest Common Subsequence)

 - 有向编辑图(Edit graph)
 算法依赖于新旧数据（定义为A和B构成的有向编辑图, 图中A为X轴, B为Y轴, 假定A和B的长度分别为m, n, 每个坐标代表了各自字符串中的一个字符. 在图中沿X轴前进代表删除A中的字符, 沿Y轴前进代表插入B中的字符. 在横坐标于纵坐标字符相同的地方, 会有一条对角线连接左上与右下两点, 表示不需任何编辑, 等价于路径长度为0. 算法的目标, 就是寻找到一个从坐标(0, 0)到(m, n)的最短路径
