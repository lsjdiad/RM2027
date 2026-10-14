import numpy as np, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
from mpl_toolkits.axes_grid1.inset_locator import inset_axes
fpp='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
font_manager.fontManager.addfont(fpp)
plt.rcParams['font.family']=font_manager.FontProperties(fname=fpp).get_name()
plt.rcParams['axes.unicode_minus']=False

Udc=12.0; D=0.10; B=1.5
CX=np.array([0,30,150,180,210,330,360],float)
CY=np.array([0, 1,  1,  0, -1, -1,  0],float)
def W(u): return np.interp(np.asarray(u,float)%360.0,CX,CY)
PHI={'A':90.0,'B':330.0,'C':210.0}
FLOAT={1:'C',2:'A',3:'B',4:'C',5:'A',6:'B'}
PWM  ={1:'A',2:'C',3:'C',4:'B',5:'B',6:'A'}
LOW  ={1:'B',2:'B',3:'A',4:'A',5:'C',6:'C'}
COL={'A':'#c62828','B':'#2e7d32','C':'#1565c0'}
PER=60.0*41.67/450.0

fig=plt.figure(figsize=(16.5,10.5))
ax1=fig.add_axes([0.055,0.55,0.925,0.335])
ax2=fig.add_axes([0.055,0.075,0.925,0.32])
fig.suptitle('RM2027 电调 · 六步换相【正确】输出波形     母线 12V · 占空比 10% · 转子匀速',
             fontsize=16.5,fontweight='bold',y=0.965)

for s in range(1,7):
    a0=(s-1)*60.0; f=FLOAT[s]
    ax1.add_patch(plt.Rectangle((a0,0),60,Udc,fc=COL[PWM[s]],ec='none',alpha=0.85))
    ax1.plot([a0,a0+60],[0,0],color=COL[LOW[s]],lw=3.4,solid_capstyle='butt')
    x=np.linspace(a0,a0+60,3000)
    ax1.plot(x,Udc/2+B*W(x-PHI[f]),color=COL[f],lw=4.0)
    v=Udc/2+B*W(x-PHI[f]); sg=np.sign(v-Udc/2); sg[sg==0]=1
    for i in np.where(np.diff(sg)!=0)[0]:
        ax1.plot(x[i],Udc/2,marker='v',ms=14,color=COL[f],mec='k',mew=1.2,zorder=9)
    ax1.text(a0+30,Udc+0.3,f'步{s}',ha='center',fontsize=11,fontweight='bold')
    ax1.text(a0+30,Udc+1.7,f'{f} 悬空',ha='center',fontsize=10,color=COL[f])

ax1.axhline(Udc/2,color='orange',lw=1.8,ls='--',zorder=2)
for y in (0,Udc): ax1.axhline(y,color='gray',lw=0.8,ls=':')
for s in range(0,361,60): ax1.axvline(s,color='gray',lw=0.9,ls=':')
ax1.set_xlim(0,360); ax1.set_ylim(-1.6,15.8); ax1.set_xticks(range(0,361,60))
ax1.set_yticks([0,6,12]); ax1.set_yticklabels(['0V','6V','12V'])
ax1.set_ylabel('相端对 GND',fontsize=12)
ax1.set_title('① 三相端电压（示波器视角）：□ 高边斩波段（占空比 10%）／粗平线 低边常通 0V／粗斜线 悬空相反电势；▽ = 过零点',
              fontsize=12.5,loc='left')
ax1.legend(handles=[
  plt.Line2D([],[],color='k',lw=0,marker='v',ms=13,label='过零点（换相后 30°）'),
  plt.Line2D([],[],color='orange',lw=1.8,ls='--',label='V0 = 6V（虚地）'),
  plt.Line2D([],[],color=COL['A'],lw=4,label='A 相'),
  plt.Line2D([],[],color=COL['B'],lw=4,label='B 相'),
  plt.Line2D([],[],color=COL['C'],lw=4,label='C 相')],
  loc='upper center',ncol=5,fontsize=10.5,framealpha=0.96)
ax1.grid(alpha=0.18)

# 放大插图：步2 里 3 个 24kHz 周期
axin=ax1.inset_axes([0.615,0.50,0.355,0.45])
a0=60.0; s=2; f=FLOAT[s]
xx=np.linspace(a0,a0+16.7,4000)
ch=np.where((xx-a0)%PER < PER*D, Udc, 0.0)
axin.fill_between(xx,0,ch,color=COL[PWM[s]],alpha=0.8,step='post',lw=0)
axin.plot(xx,ch,color=COL[PWM[s]],lw=1.3)
axin.plot(xx,np.zeros_like(xx),color=COL[LOW[s]],lw=3.0)
axin.plot(xx,Udc/2+B*W(xx-PHI[f]),color=COL[f],lw=3.2)
axin.axhline(Udc/2,color='orange',lw=1.1,ls='--')
axin.set_xlim(a0,a0+16.7); axin.set_ylim(-1.5,14)
axin.set_yticks([0,6,12]); axin.set_yticklabels(['0','6V','12V'],fontsize=8)
axin.set_xticks([]); axin.tick_params(labelsize=8)
axin.set_title('放大：真实 24kHz 斩波（3 个周期）',fontsize=9)
axin.grid(alpha=0.2)

# 下栏
for s in range(1,7):
    a0=(s-1)*60.0; x=np.linspace(a0,a0+60,6000); f=FLOAT[s]
    d=B*W(x-PHI[f]); ax2.plot(x,d,color=COL[f],lw=4.0)
    ax2.text(a0+30,0.12 if d[len(d)//2]>0 else -0.26,f,color=COL[f],ha='center',fontsize=14,fontweight='bold')
    sg=np.sign(d); sg[sg==0]=1
    for i in np.where(np.diff(sg)!=0)[0]:
        ax2.plot(x[i],0,marker='o',ms=12,color=COL[f],mec='k',mew=1.2,zorder=9)
ax2.axhline(0,color='orange',lw=1.9,ls='--')
for s in range(0,361,60): ax2.axvline(s,color='gray',lw=0.9,ls=':')
ax2.set_xlim(0,360); ax2.set_ylim(-B*1.55,B*1.55); ax2.set_xticks(range(0,361,60))
ax2.set_yticks([-B,0,B]); ax2.set_yticklabels([f'−{B}V','0 = 过零',f'+{B}V'])
ax2.set_xlabel('转子电角度 (°)',fontsize=12)
ax2.set_ylabel('悬空相反电势 − V0',fontsize=12)
ax2.set_title('② 只留悬空相（闭环判据真正看的东西）：每个换相步里它必定在步内 30°（=换相后半个步长）处过零 —— 闭环就抓这一下',
              fontsize=12.5,loc='left')
ax2.grid(alpha=0.18)

plt.savefig('sixstep_correct.png',dpi=125,bbox_inches='tight')
print('OK')
