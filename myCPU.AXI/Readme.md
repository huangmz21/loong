# 说明
## 本次修改7.14
1. 化简了`inst_undef`判断的数据通路
2. 利用了`alu.v`里的`overflow`信号，化简了溢出异常的判断，即`es_overflow`
3. `mycpu_top.v`的输入端口按照规定添加`wire [5:0] ext_in`
4. 采用了mips规定的固定映射地址机制

## 结果
func_test 全部通过

