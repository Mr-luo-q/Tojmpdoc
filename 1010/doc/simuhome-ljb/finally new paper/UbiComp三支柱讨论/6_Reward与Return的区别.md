# Reward 与 Return 的区别

## 1. 一句话结论

`reward` 是环境在每一步给出的即时反馈，一步一个数值。

`return`（中文常译“回报”或“累积回报”）是从某个时刻开始，把之后每一步的 reward 按折扣累加出来的目标值。

```
reward：这一步拿到多少
return：从这一刻开始往后总共能拿到多少
```

每一步都有 reward，这句话没错；但这些 reward 是构成 return 的材料，单个 reward 本身还不等于 return。

术语上要留意：部分中文资料把 reward 也译作“回报”，同一个词有时指代两个概念。本文统一采用 reward = 奖励（即时信号），return = 回报（累积目标值）。

## 2. 用一条轨迹看

假设智能家居任务是“二十分钟内把厨房降到 24°C”，折扣因子 γ=0.99。某条轨迹如下：

```
step    action                  reward     说明
 t=0    开空调，设定 24°C        -1.0      耗电、噪声，温度还没降
 t=1    等待                     -0.5      温度在降，但还没达标
 t=2    开门让空气流通            -0.5      仍差一点
 t=3    等待                     +3.0      厨房进入目标区间
 t=4    本局结束（terminated）
```

每一步的 reward 分别是 `-1.0, -0.5, -0.5, +3.0`，这些是环境在单步给出的信号。从 t=0 看整段收益，是把它们折现累加：

```
G_0 = r_0 + γ·r_1 + γ²·r_2 + γ³·r_3
    = -1.0 + 0.99·(-0.5) + 0.99²·(-0.5) + 0.99³·(3.0)
    ≈ 0.93

G_1 = r_1 + γ·r_2 + γ²·r_3 ≈ 1.95
G_2 = r_2 + γ·r_3          ≈ 2.47
G_3 = r_3                  = 3.00     # terminated 之后价值为 0
```

`G_0` 是从 t=0 出发的 return，`G_1` 是从 t=1 出发的 return。同一条轨迹里，每个时刻都可以有自己的一份 return-to-go（从该时刻开始的后续回报）。它们都不是某一步的 reward。

## 3. 为什么要把两者分开

分开的原因是：单看即时 reward 会做出糟糕的决策。

```
只看即时 reward：
  开空调 → -1.0，不开空调 → 0.0
  结论：什么都不做最划算

看 return：
  开空调 → 前几步都是负分，最后任务达成 +3.0
  整段回报为正，策略应该学会接受短期负奖励
```

智能家居任务里这类时间错位特别常见：开空调、预热、通风、等待，前几步通常是负奖励，效果要过一段时间才出现。RL 要优化的目标是期望 return：

```
J(θ) = E[ G_0 ]           # 从回合开始到结束的累积回报
```

策略参数 θ 的更新方向是让这个期望变大，而不是让每一步的 reward 都立刻变大。如果只看单步 reward，模型会学到“不做任何耗能动作”，这在长期任务里是错的。

## 4. 回报的几种算法形式

同一串 reward，可以按不同方式合成 return，区别在于回头看多远：

```
蒙特卡洛回报（MC）：
  G_t = r_t + γ·r_{t+1} + γ²·r_{t+2} + ...
  一直加到本局结束，使用采到的全部真实 reward

n 步回报：
  G_t ≈ r_t + γ·r_{t+1} + ... + γ^{n-1}·r_{t+n-1} + γ^n·V(s_{t+n})
  前 n 步用真实 reward，之后用价值函数估计

TD 回报：
  G_t ≈ r_t + γ·V(s_{t+1})
  只用一步真实 reward，其余都由价值函数估计

GAE：
  把不同步长的回报加权组合，兼顾偏差与方差
```

这三种形式都在回答同一个问题：“从这一刻往后，总共能拿到多少？”它们的区别是用多少真实 reward 去算、用多少估计去补。

## 5. 蒙特卡洛回报与搜索树的关系

两者共享 “Monte Carlo” 这个名字，含义落在不同层面。

在 RL 里，Monte Carlo 指的是一类方法：用随机采样的结果估计期望。MC return 是这类方法最基础的产物：跑完一条轨迹，把 reward 折现累加，得到从某个时刻出发的回报估计。

MCTS（Monte Carlo Tree Search）是把这类采样思想用于“决策时的前瞻搜索”：在真正行动之前，用模拟在决策树上探索若干条可能路径，再根据模拟结果决定当前动作。树中每次模拟走到终局，都会产生一段回报，这段回报被回传（backup）到路径上的节点，更新节点的价值估计与访问次数。

```
Monte Carlo（用采样估计期望）
  ├── MC return：一条轨迹的 reward 折现求和
  ├── Monte Carlo evaluation：多条轨迹的 return 取平均
  └── MCTS：用采样构造搜索树，用 return 更新节点统计
```

MCTS 一轮迭代的四个阶段：

```
selection：按 UCB 等规则从根节点往下选
expansion：扩展一个尚未访问的节点
simulation / rollout：从该节点模拟到终局，产生一段 return
backpropagation：把 return 沿路径回传，更新节点价值与访问计数
```

第三步用的就是 Monte Carlo 意义上的回报：把模拟路径上的 reward 折现累加；第四步把回报写入树节点，多次模拟的平均回报构成节点的价值估计，下一步 selection 依据这些统计继续搜索。

两者也有明确区别：

```
MC return 不需要搜索树
  REINFORCE / PPO 直接对采样轨迹算 return

MCTS 不必须使用 rollout return
  AlphaZero 用价值网络给节点估值，
  MuZero 用学到的模型预测价值与奖励；
  这类 backup 更接近 TD / 价值估计，而非纯 MC

评估对象不同
  MC return 通常针对一条完整 episode，
  MCTS 的 return 针对从某个树节点出发的一条模拟路径，
  最后往往取平均、加探索项，得到的是统计量
```

放回智能家居场景：HomeFlow 的 MCTS-Flow 用树搜索合成多轮可验证轨迹，树节点扩展对应候选的动作与对话步骤，模拟到终局后用环境验证结果评分。这个评分就是节点上的回报估计。评分来自 rollout 的验证结果时，它属于 Monte Carlo return 用法；评分来自价值模型时，它属于 value backup。MCTS 与 MC return 的关系可以概括为：搜索树负责决定“往哪条路上多探索”，MC return 负责给探索过的路径打分。

## 6. 价值和回报的关系

RL 里还常见 `V` 和 `Q`，它们和 return 的关系是：

```
V(s)   = 在状态 s 下，未来回报的期望值
Q(s,a) = 在状态 s 下先做动作 a，之后未来回报的期望值
```

所以 critic 学的是“期望回报”，不是某一步的 reward。反过来，把 V 和 Q 代进 n 步回报，就能在没有采到后续奖励时把回报补完整。

## 7. 为什么回报不总能由一条样本直接算出来

如果本局以 `terminated` 结束，终止之后没有以后了，回报可以从 reward 序列直接加到底：

```
... → r_{T-1} → r_T →（terminal）
G_T = 0
```

如果本局以 `truncated` 结束，采样停了，任务没停：

```
... → r_{T-1} → r_T →（truncated）
G_T ≈ r_T + γ·V(s_{T+1})
       样本里没有 r_{T+1} 之后的奖励，
       只能用 V 估计截断之后的那一段
```

这就是“截断处还要估计后续价值”的含义：不是这次采样里的后续知道了，而是那部分未来根本没被采到。

## 8. 伪代码：从 reward 序列算 return

```python
rewards = [-1.0, -0.5, -0.5, 3.0]      # 一条轨迹上逐步的即时奖励
gamma = 0.99                            # 折扣因子

returns = [0.0] * len(rewards)          # 每个时刻的 return-to-go

G = 0.0                                 # terminated 结尾，终止后价值为 0
for t in reversed(range(len(rewards))):
    G = rewards[t] + gamma * G          # 从后往前累加
    returns[t] = G

# returns ≈ [0.93, 1.95, 2.47, 3.00]
# 每个动作对应的训练目标，是它自己的 return-to-go
```

注意循环方向：从轨迹末尾往前推。每加一步，就是把“再往后会拿到什么”折算进当前时刻的回报里。

## 9. compute_returns 是对每个 transition 计算吗

是。对一条轨迹，每个 transition 都对应一个 return-to-go。它回答的问题是：如果我现在处在 transition t，从这一刻开始往后总共能拿到多少回报。

```
transition_t： (obs_t, action_t, reward_t, next_obs_t, terminated, truncated)

return-to-go：
  G_t = reward_t + γ·reward_{t+1} + γ²·reward_{t+2} + ...
```

还是用上面那条四步轨迹，把每个 transition 的 return-to-go 都列出来：

```
step   reward   return-to-go   计算过程
 t=0   -1.0     0.93           G0 = r0 + γ·G1
 t=1   -0.5     1.95           G1 = r1 + γ·G2
 t=2   -0.5     2.47           G2 = r2 + γ·G3
 t=3   +3.0     3.00           G3 = r3（terminated 后价值归零）
```

从后往前算的过程是：

```
G3 = r3
G2 = r2 + γ · G3
G1 = r1 + γ · G2
G0 = r0 + γ · G1
```

所以 `compute_returns` 返回的不是“整条轨迹只有开头那一个回报”，而是轨迹上每个时刻各有一个 return-to-go。transition t 对应的训练目标由 `G_t` 构成：动作 a_t 的好坏，由它之后能拿到的总收益来评价。

计算时最重要的两个细节：

```python
# 先确定轨迹结尾之后的价值
if trajectory[-1].truncated:
    G = V(trajectory[-1].next_obs)   # 被截断，后面仍有未来，需要估计
else:
    G = 0.0                          # terminated，终止后没有未来

for t in reversed(range(len(trajectory))):
    G = trajectory[t].reward + gamma * G
    returns[t] = G                   # transition t 的 return-to-go
```

第一处细节是结尾：`terminated` 结尾时从 0 开始累加，`truncated` 结尾时从 `V(next_obs)` 开始，因为采样停在这里，任务还在继续。第二处细节是方向：必须从后往前累加，因为 `G_t` 依赖 `G_{t+1}`。

batch 里通常不只一条轨迹，计算时要按轨迹分别进行：

```
batch
  ├── trajectory A：t=0..3，terminated 结束
  └── trajectory B：t=0..5，truncated 结束

compute_returns 对 A、B 各算一遍，
不能用 A 的结尾继续接 B 的开头；
识别边界的标志就是 terminated or truncated。
```

最后，不同的 RL 算法使用 `G_t` 的方式不同，但都要落到每条 transition 上：

```
REINFORCE：直接用 G_t 更新动作概率
A2C：用 advantage = G_t - V(obs_t)
PPO：用 GAE 把多步 return 与价值估计组合成 advantage
DQN：用 n 步目标 r_t + γ·max Q(next_obs, ·) 做价值回归
```

所以“每条 transition 上有 reward”和“每条 transition 上有 return”是两个不同层次：前者是这一步的即时信号，后者是从这一步往后的累积目标。`compute_returns` 负责把前者加工成后者。

## 10. 回到 buffer 里的那条样本

```
一条 transition：
  (obs, action, reward, next_obs, terminated, truncated)

一条轨迹：
  [transition_0, transition_1, ..., transition_T]
```

一条 transition 只带一个 `reward`，这是它所在那一步的即时信号。Return 不是在单条 transition 里产生的，而是把一条轨迹上多个 transition 的 `reward` 串起来、折现累加得到的。训练时最常见的用法是：用 return 或它的估计值构造 advantage，决定这个动作应该被强化还是被削弱。

所以三句话可以收束整个问题：

```
每一步有 reward —— 对，环境按 step 给即时反馈
reward 就是回报吗 —— 不是，reward 是原料，return 是折现累加后的目标值
为什么不能只看 reward —— 短期负奖励换来的长期任务达成，只有 return 能表达
```
