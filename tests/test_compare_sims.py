import numpy as np
from nose.tools import * 

import sim2600
from sim2600 import sim2600Console
from sim2600 import params, sim6502
import sim2600.sim6502

def compare_sims(s1func, s2func, ITERS=100):

    for rom in [params.ROMS_DONKEY_KONG, params.ROMS_SPACE_INVADERS, 
                params.ROMS_PITFALL]:

        s1 = s1func(rom)
        s2 = s2func(rom)

        for i in range(ITERS):
            s1.advanceOneHalfClock()
            s2.advanceOneHalfClock()
            s1_state =  s1.sim6507.getWiresState() #  # getWireState()
            s2_state =  s2.sim6507.getWiresState() #  # getWireState()

            assert_equal(s1_state, s2_state)


def test_compare_simple_simple():
    """
    Just compare our default simulator agaginst
    itself
    """
    s1 = lambda x: sim2600Console.Sim2600Console(x)
    
    compare_sims(s1, s1)


def test_compare_list_sets():
    """
    Just compare our default simulator agaginst
    itself
    """
    s1 = lambda x: sim2600Console.Sim2600Console(x, sim6502.Sim6502)
    s2 = lambda x: sim2600Console.Sim2600Console(x, sim6502.Sim6502Sets)
    
    compare_sims(s1, s2)

def test_compare_list_mine():
    """
    Just compare our default simulator agaginst
    itself
    """
    s1 = lambda x: sim2600Console.Sim2600Console(x, sim6502.Sim6502)
    s2 = lambda x: sim2600Console.Sim2600Console(x, sim6502.MySim6502)
    
    compare_sims(s1, s2)

