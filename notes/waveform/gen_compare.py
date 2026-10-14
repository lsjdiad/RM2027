import numpy as np, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
fpp='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
font_manager.fontManager.addfont(fpp)
plt.rcParams['font.family']=font_manager.FontProperties(fname=fpp).get_name()
plt.rcParams['axes.unicode_minus']=False

Udc=12.0; B=1.5
CX=np.array([0,30,150,180,210,330,360],float); CY=np.array([0,1,1,0,-1,-1,0],float)
def W(u): return np.interp(np.asarray(u,float)%360.0,CX,CY)
PHI={'A':90.0,'B':330.0,'C':210.0}
FLOAT={1:'C',2:'A',3:'B',4:'C',5:'A',6:'B'}
COL={'A':'#c62828','B':'#2e7d32','C':'#1565c0'}

fig,ax=plt.subplots(2,1,figsize=(13,8.2),sharex=True)
fig.suptitle('悬空相反电势（相对 V0）：正确波形  vs  实测的"起步自锁"',
             fontsize=15,fontweight='bold',y=0.97)

# 上：正确
for s in range(1,7):
    a0=(s-1)*60.0; x=np.linspace(a0,a0+60,4000); f=FLOAT[s]
    d=B*W(x-PHI[f]); ax[0].plot(x,d,color=COL[f],lw=3.4)
    sg=np.sign(d); sg[sg==0]=1
    for i in np.where(np.diff(sg)!=0)[0]:
        ax[0].plot(x[i],0,marker='o',ms=11,color=COL[f],mec='k',mew=1.1,zorder=8)
    ax[0].text(a0+30, 0.12 if d[len(d)//2]>0 else -0.26, f, color=COL[f],
               ha='center', fontsize=12, fontweight='bold')
ax[0].axhline(0,color='orange',lw=1.8,ls='--')
ax[0].set_ylim(-B*1.6,B*1.6); ax[0].set_yticks([-B,0,B])
ax[0].set_yticklabels([f'−{B}V','0=过零',f'+{B}V'])
ax[0].set_title('① 正确：悬空相反电势每个换相步都穿过 0（步内 30°）⇒ 闭环能认到 ⇒ 能交棒',
                fontsize=12,loc='left')
ax[0].grid(alpha=0.2)

# 下：自锁（实测）
x=np.linspace(0,360,3000)
ax[1].axhline(0,color='orange',lw=1.8,ls='--')
noise=0.02*np.sin(x*40)+0.015*np.cos(x*97)   # 实测那点抖动 → 画成极小噪声
ax[1].plot(x,noise,color='#888888',lw=1.6)
ax[1].annotate('实测 ≈ 0（恒 0.5V 一带），从不穿过 0',
               xy=(180,0), xytext=(120,0.55), fontsize=12, color='#444',
               arrowprops=dict(arrowstyle='->',color='#444'))
ax[1].text(180,-0.75,'step 每 22.5ms 才走一步（≈7 RPM）\n电机根本没转起来 ⇒ 没有反电势',
           ha='center',fontsize=12,color='#c62828',fontweight='bold')
ax[1].set_ylim(-B*1.6,B*1.6); ax[1].set_yticks([-B,0,B])
ax[1].set_yticklabels([f'−{B}V','0=过零',f'+{B}V'])
ax[1].set_xlim(0,360); ax[1].set_xticks(range(0,361,60))
ax[1].set_xlabel('转子电角度 (°)',fontsize=12)
ax[1].set_title('② 实测（闭环"起步即自锁"）：反电势恒 ≈0，状态永不翻转 ⇒ zero_crosses 恒 0 ⇒ 一直靠超时硬踹',
                fontsize=12,loc='left')
ax[1].grid(alpha=0.2)

plt.tight_layout(rect=[0,0,1,0.95])
plt.savefig('zc_compare.png',dpi=125,bbox_inches='tight')
print('OK')
