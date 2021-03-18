from .mainSim import printStartupMsg
from .compareSim import MainSim

printStartupMsg()
sim = MainSim()
sim.runsim(100)
print('Exiting mainSim.py')
