# FPGA self-balancing car (DE0-Nano)

Public copy of the school DE0-Nano two-wheel balancer.

**Start here:** [START-HERE.md](START-HERE.md)

Inner loop is cascade PID + complementary filter on `GPIO_1` / JP2. No neural net on the FPGA.

Ask GitHub Grok:

```
Read START-HERE.md then RULEBOOK-GROK-CLI-TO-BALANCE.md. Stay in frozen scope.
Explain the cascade PID in pid_cascade.v and how STAND_OFFSET is applied in top_module.v / comp_filter.v.
```
