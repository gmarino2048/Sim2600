# Copyright (c) 2014 Greg James, Visual6502.org
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

import os, pickle, traceback
from array import array
import numpy as np
cimport numpy as np
from libcpp.vector cimport vector
from libcpp.set cimport set as stdset
import cython

import copy
import sys

cpdef enum WireState:
    PULLED_HIGH  = 1 << 0 # 1 
    PULLED_LOW     = 1 << 1 # 2
    GROUNDED       = 1 << 2 # 4
    HIGH           = 1 << 3 # 8
    FLOATING_HIGH  = 1 << 4 # 16
    FLOATING_LOW   = 1 << 5 # 32
    FLOATING       = 1 << 6 # 64

cdef int ANY_HIGH = (FLOATING_HIGH | HIGH | PULLED_HIGH)
cdef int ANY_LOW  = (FLOATING_LOW | GROUNDED | PULLED_LOW)
class Wire:

    def __init__(self, idIndex, name, controlTransIndices, transGateIndices, pulled):
        self.index = idIndex
        self.name = name

        # Transistors that switch other wires into connection with this wire
        self.ctInds = list(controlTransIndices)

        # Transistors whos gate is driven by this wire
        self.gateInds = list(transGateIndices) # FOR AN INSANE REASON WHEN THIS IS A SET IT FAILS

        # pulled reflects whether or not the wire is connected to
        # a pullup or pulldown.
        self._pulled = pulled

        # state reflects the logical state of the wire as the 
        # simulation progresses.
        self._state = pulled

    def __repr__(self):
        rstr = 'Wire %d "%s": %d  ct %s gates %s'%(self.index, self.name,
               self.state, str(self.ctInds), str(self.gateInds))
        return rstr


class NmosFet:
    GATE_LOW  = 0
    GATE_HIGH = 1 << 0

    def __init__(self, idIndex, side1WireIndex, side2WireIndex, gateWireIndex):
        
        # Wires switched together when this transistor is on
        self.side1WireIndex = side1WireIndex
        self.side2WireIndex = side2WireIndex
        self.gateWireIndex  = gateWireIndex

        self._gateState = NmosFet.GATE_LOW
        self.index = idIndex

    def __repr__(self):
        rstr = 'NFET %d: %d gate %d [%d, %d]'%(self.index, self.state,
               self.gateWireIndex, self.size1WireIndex, self.side2WireIndex)
        return rstr



class CircuitSimulator(object):
    def __init__(self):
        self.name = ''
        self._wireList = None        # wireList[i] is a Wire.  wireList[i].index = i
        self._transistorList = None
        self.wireNames = dict()     # key is string wire names, value is integer wire index
        self.halfClkCount = 0       # the number of half clock cycles (low to high or high to low)
                                    # that the simulation has run


        # Performance / diagnostic info as sim progresses
        self.numAddWireToGroup = 0
        self.numAddWireTransistor = 0
        # General sense of how much work it's doing
        self.numWiresRecalculated = 0
        
        # If not None, call this to add a line to some log
        self.callback_addLogStr = None   # callback_addLogStr ('some text')


    def createStateArrays(self):
        # create the transistor and wire state arrays
        self._wireState = np.zeros(len(self._wireList), dtype=np.uint8)
        self._wireState[:] = [w._state for w in self._wireList]
        self._wirePulled = np.zeros(len(self._wireList), dtype=np.uint8)
        self._wirePulled[:] = [w._pulled for w in self._wireList] # fixme better way?

        self._transistorState = np.zeros(len(self._transistorList), dtype=np.uint8)
        self._transistorState[:] = [t._gateState for t in self._transistorList]
        
        
    def clearSimStats(self):
        self.numAddWireToGroup = 0
        self.numAddWireTransistor = 0

    def getWireIndex(self, wireNameStr):
        return self.wireNames[wireNameStr]

    def recalcNamedWire(self, wireNameStr):
        self.recalcWireList([self.wireNames[wireNameStr]])

    def recalcWireNameList(self, wireNameList):
        wireList = [None] * len(wireNameList)
        i = 0
        for name in wireNameList:
            wireList[i] = self.wireNames[name]
            i += 1
        self.recalcWireList (wireList)

    def recalcAllWires(self):
        """ Not fast.  Meant only for setting initial conditions """
        wireInds = []
        for ind, wire in enumerate(self._wireList):
            if wire is not None:
                wireInds.append(ind)
        self.recalcWireList (wireInds)
        
    def recalcWireList(self, nwireList):
        
        self.calculator.recalcWireList(nwireList, self.halfClkCount)


    def recalcWire(self, wireIndex):
        self.recalcWireList([wireIndex])

    def floatWire(self, wireIndex):
        i = wireIndex
        wire = self._wireList[i]

        if self._wirePulled[i] == PULLED_HIGH:
            self._wireState[i] = PULLED_HIGH
        elif self._wirePulled[i] == PULLED_LOW:
            self._wireState[i] = PULLED_LOW
        else:
            state = self._wireState[i]
            if state == GROUNDED or state == PULLED_LOW:
                self._wireState[i] = FLOATING_LOW
            if state == HIGH or state == PULLED_HIGH:
                self._wireState[i] = FLOATING_HIGH

    # setHighWN() and setLowWN() do not trigger an update
    # of the simulation.
    def setHighWN(self, n):
        if n in self.wireNames:
            wireIndex = self.wireNames[n]
            self._wireState[wireIndex] = PULLED_HIGH
            self._wirePulled[wireIndex] = PULLED_HIGH 


            return
        raise Exception("WHEN DO WE EVER GET HERE")

        # assert type(n) == type(1), 'wire thing %s'%str(n)
        # wire = self._wireList[n]
        # if wire is not None:
        #     wire._setHigh()
        # else:
        #     print 'ERROR - trying to set wire None high'

    def setLowWN(self, n):
        #FIXME WHAT THE HELL IS THIS ? 
        if n in self.wireNames:
            wireIndex = self.wireNames[n]
            self._wireState[wireIndex] = PULLED_LOW
            self._wirePulled[wireIndex] = PULLED_LOW 

            return
        raise Exception("WHEN DO WE EVER GET HERE")
        # assert type(n) == type(1), 'wire thing %s'%str(n)
        # wire = self._wireList[n]
        # if wire is not None:
        #     wire.setLow()
        # else:
        #     print 'ERROR - trying to set wire None low'

    def _setPulledHighOrLow(self, idx, boolHigh):
        if boolHigh == True:
            self._wirePulled[idx] = PULLED_HIGH
            self._wireState[idx]  = PULLED_HIGH
        elif boolHigh == False:
            self._wirePulled[idx] = PULLED_LOW
            self._wireState[idx]  = PULLED_LOW

    def setHigh(self, wireIndex):
        self._setPulledHighOrLow(wireIndex, True)

    def setLow(self, wireIndex):
        self._setPulledHighOrLow(wireIndex, False)

    def setPulled(self, wireIndex, boolHighOrLow):
        self._setPulledHighOrLow(wireIndex, boolHighOrLow)

    def setPulledHigh(self, wireIndex):
        self._setPulledHighOrLow(wireIndex, True)

    def setPulledLow(self, wireIndex):
        self._setPulledHighOrLow(wireIndex, False)

    def isHigh(self, wireIndex):
        return bool((self._wireState[wireIndex] & (ANY_HIGH)))

    def isLow(self, wireIndex):
        return bool( self._wireState[wireIndex] & ANY_LOW)

    def isHighWN(self, n):
        raise NotImplementedError()
        if n in self.wireNames:
            wireIndex = self.wireNames[n]
            return self._wireList[wireIndex]._isHigh()

        assert type(n) == type(1), 'ERROR: if arg to isHigh is not in ' + \
            'wireNames, it had better be an integer'
        wire = self._wireList[n]
        assert wire is not None
        return wire.isHigh()
        
    def isLowWN(self, n):
        raise NotImplementedError()
        if n in self.wireNames:
            wireIndex = self.wireNames[n]
            return self._wireList[wireIndex]._isLow()

        wire = self._wireList[n]
        assert wire is not None
        return wire.isLow()

    # TODO: rename to getNamedSignal (name, lowBitNum, highBitNum) ('DB',0,7) 
    # TODO: elim or use wire indices
    # Use for debug and to examine busses.  This is slow. 
    def getGen(self, strSigName, size):
        raise NotImplementedError()
        data = 0
        for i in xrange(size, -1, -1):
            data = data * 2
            bit = '%s%d'%(strSigName,i)
            if self.isHighWN(bit):
                data = data + 1
        return data

    def setGen(self, data, string, size):
        raise NotImplementedError()
        d = data
        for i in xrange(size):
            bit = '%s%d'%(string,i)
            if (d & 1) == 1:
                self.setHigh(bit)
            else:
                self.setLowWN(bit)
            d = d / 2
            
    def updateWireNames (self, wireNames):        
        for j in wireNames:
            i = 0
            nameStr = j[0]
            for k in j[1:]:
                name = '%s%d'%(nameStr,i)
                self._wireList[k].name = name
                self.wireNames[name] = k
                i += 1

    def getWiresState(self):
        return np.array(self._wireState)
 
    def getPulledState(self):
        return np.array(self._wirePulled)

    def getTransistorState(self):
        return np.array(self._transistorState)

    def loadCircuit (self, filePath):

        if not os.path.exists(filePath):
            raise Exception('Could not find circuit file: %s  from cwd %s'%
                            (filePath, os.getcwd()))
        print 'Loading %s' % filePath
        
        of = open (filePath, 'rb')
        rootObj = pickle.load (of)
        of.close()

        numWires = rootObj['NUM_WIRES']
        nextCtrl = rootObj['NEXT_CTRL']
        noWire = rootObj['NO_WIRE']
        wirePulled = rootObj['WIRE_PULLED']
        wireCtrlFets = rootObj['WIRE_CTRL_FETS']
        wireGates = rootObj['WIRE_GATES']
        wireNames = rootObj['WIRE_NAMES']
        numFets = rootObj['NUM_FETS']
        fetSide1WireInds = rootObj['FET_SIDE1_WIRE_INDS']
        fetSide2WireInds = rootObj['FET_SIDE2_WIRE_INDS']
        fetGateWireInds = rootObj['FET_GATE_INDS']
        numNoneWires = rootObj['NUM_NULL_WIRES']

        l = len(wirePulled)
        assert l == numWires, 'Expected %d entries in wirePulled, got %d'%(numWires, l)
        l = len(wireNames)
        assert l == numWires, 'Expected %d wireNames, got %d'%(numWires, l)

        l = len(fetSide1WireInds)
        assert l == numFets, 'Expected %d fetSide1WireInds, got %d'%(numFets, l)
        l = len(fetSide2WireInds)
        assert l == numFets, 'Expected %d fetSide2WireInds, got %d'%(numFets, l)
        l = len(fetGateWireInds)
        assert l == numFets, 'Expected %d fetGateWireInds, got %d'%(numFets, l)

        self._wireList = [None] * numWires

        i = 0
        wcfi = 0
        wgi = 0
        while i < numWires:
            numControlFets = wireCtrlFets[wcfi]
            wcfi += 1
            controlFets = set()
            n = 0
            while n < numControlFets:
                controlFets.add(wireCtrlFets[wcfi])
                wcfi += 1
                n += 1
            tok = wireCtrlFets[wcfi]
            wcfi += 1
            assert tok == nextCtrl, 'Wire %d read 0x%X instead of 0x%X at end of ctrl fet segment len %d: %s'%(
                i, tok, nextCtrl, numControlFets, str(wireCtrlFets[wcfi-1-numControlFets-1:wcfi]))

            numGates = wireGates[wgi]
            wgi += 1
            gates = set()
            n = 0
            while n < numGates:
                gates.add(wireGates[wgi])
                wgi += 1
                n += 1
            tok = wireGates[wgi]
            wgi += 1
            assert tok == nextCtrl, 'Wire %d Read 0x%X instead of 0x%X at end of gates segment len %d: %s'%(
                i, tok, nextCtrl, numGates, str(wireGates[wgi-1-numGates-1:wgi]))

            if len(wireCtrlFets) == 0 and len(gates) == 0:
                assert wireNames[i] == ''
                self._wireList[i] = None
            else:
                self._wireList[i] = Wire(i, wireNames[i], controlFets, gates, wirePulled[i])
                self.wireNames[wireNames[i]] = i
            i += 1

        self._transistorList = [None] * numFets
        i = 0
        while i < numFets:
            s1 = fetSide1WireInds[i]
            s2 = fetSide2WireInds[i]
            gate = fetGateWireInds[i]
            
            if s1 == noWire:
                assert s2 == noWire
                assert gate == noWire
            else:
                self._transistorList[i] = NmosFet(i, s1, s2, gate)
            i += 1

        assert 'VCC' in self.wireNames
        assert 'VSS' in self.wireNames
        self.vccWireIndex = self.wireNames['VCC']
        self.gndWireIndex = self.wireNames['VSS']
        self._wireList[self.vccWireIndex]._state = HIGH
        self._wireList[self.gndWireIndex]._state = GROUNDED
        for transInd in self._wireList[self.vccWireIndex].gateInds:
            self._transistorList[transInd]._gateState = NmosFet.GATE_HIGH

        self.lastWireGroupState = [-1] * numWires

        # create the calculator
        self.createStateArrays()
        self.calculator  = WireCalculator(self._wireList, 
                                          self._transistorList, 
                                          self._wireState, 
                                          self._wirePulled, 
                                          self._transistorState, 
                                          self.gndWireIndex,
                                          self.vccWireIndex)

        return rootObj


    def writeCktFile(self, filePath):
 
        rootObj = dict()
        
        numWires = len(self._wireList)
        nextCtrl = 0xFFFE

        # 'B' for unsigned integer, minimum of 1 byte
        wirePulled = array('B', [0] * numWires)

        # 'I' for unsigned int, minimum of 2 bytes
        wireControlFets = array('I')
        wireGates = array('I')
        numNoneWires = 0
        wireNames = []

        for i, wire in enumerate(self._wireList):
            if wire is None:
                wireControlFets.append(0)
                wireControlFets.append(nextCtrl)
                wireGates.append(0)
                wireGates.append(nextCtrl)
                numNoneWires += 1
                wireNames.append('')
                continue

            wirePulled[i] = wire.pulled

            wireControlFets.append(len(wire.ins))
            for transInd in wire.ins:
                wireControlFets.append(transInd)
            wireControlFets.append(nextCtrl)

            wireGates.append(len(wire.outs))
            for transInd in wire.outs:
                wireGates.append(transInd)
            wireGates.append(nextCtrl)

            wireNames.append(wire.name)

        noWire = 0xFFFD
        numFets = len(self._transistorList)
        fetSide1WireInds = array('I', [noWire] * numFets)
        fetSide2WireInds = array('I', [noWire] * numFets)
        fetGateWireInds  = array('I', [noWire] * numFets)

        for i, trans in enumerate(self._transistorList):
            if trans is None:
                continue
            fetSide1WireInds[i] = trans.c1
            fetSide2WireInds[i] = trans.c2
            fetGateWireInds[i] = trans.gate

        rootObj['NUM_WIRES'] = numWires
        rootObj['NEXT_CTRL'] = nextCtrl
        rootObj['NO_WIRE'] = noWire
        rootObj['WIRE_PULLED'] = wirePulled
        rootObj['WIRE_CTRL_FETS'] = wireControlFets
        rootObj['WIRE_GATES'] = wireGates
        rootObj['WIRE_NAMES'] = wireNames
        rootObj['NUM_FETS'] = numFets
        rootObj['FET_SIDE1_WIRE_INDS'] = fetSide1WireInds
        rootObj['FET_SIDE2_WIRE_INDS'] = fetSide2WireInds
        # Extra info to verify the data and connections
        rootObj['FET_GATE_INDS'] = fetGateWireInds
        rootObj['NUM_NULL_WIRES'] = numNoneWires

        of = open(filePath, 'wb')
        pickle.dump(rootObj, of)
        of.close()



#cpdef enum TransistorIndexPos:
cdef int    TW_GATE = 0
cdef int    TW_S1 = 1
cdef int    TW_S2 = 2

cdef class WireCalculator:
    cdef object _wireList
    cdef np.uint8_t[:] _wireState
    cdef np.uint8_t[:] _wirePulled
    cdef np.uint8_t[:] _transistorState
    cdef np.uint8_t[:] recalcArray
    cdef int gndWireIndex
    cdef int vccWireIndex
    cdef int numAddWireToGroup
    cdef int numAddWireTransistor
    cdef int numWiresRecalculated
    cdef object callback_addLogStr
    cdef int recalcCap
    cdef vector[int] recalcOrderStack
    cdef np.uint8_t[:] newRecalcArray
    cdef vector[int] newRecalcOrderStack
    cdef np.int32_t[:, :] _transistorWires
    cdef np.int32_t[:] _numWires

    def __init__(self, wireList, transistorList, 
                 wireState, wirePulled, transistorState, # all references
                 gndWireIndex,
                 vccWireIndex):

        self._numWires = np.zeros(len(wireList), dtype=np.int32)

        self._wireList = wireList
        #self._transistorList = transistorList
        self._wireState = wireState
        self._wirePulled = wirePulled
        self._transistorState = transistorState

        self.recalcArray = None

        self.gndWireIndex = gndWireIndex
        self.vccWireIndex = vccWireIndex

        # Performance / diagnostic info as sim progresses
        self.numAddWireToGroup = 0
        self.numAddWireTransistor = 0
        # General sense of how much work it's doing
        self.numWiresRecalculated = 0
        
        # If not None, call this to add a line to some log
        self.callback_addLogStr = None   # callback_addLogStr ('some text')

        self.recalcCap = len(self._transistorState)
        # Using lists [] for these is faster than using array('B'/'L', ...)
        self.recalcArray = np.zeros(self.recalcCap, dtype=np.uint8) # [False] * self.recalcCap
        #self.recalcOrderStack = []
        self.newRecalcArray = np.zeros(self.recalcCap, dtype=np.uint8) # [0] * self.recalcCap
        #self.newRecalcOrderStack = []

        # count the wires
        for wi, w in enumerate(wireList):
            self._numWires[wi] = len(w.ctInds) + len(w.gateInds)
        self._prepForRecalc()


        # create the transistor index array
        self._transistorWires = np.zeros((len(transistorList), 
                                          3), dtype=np.int32)
        for ti, t in enumerate(transistorList):
            self._transistorWires[ti, TW_GATE] = t.gateWireIndex
            self._transistorWires[ti, TW_S1] = t.side1WireIndex
            self._transistorWires[ti, TW_S2] = t.side2WireIndex
            
    cdef _prepForRecalc(self):
        self.recalcOrderStack.clear() #  = []
        self.newRecalcOrderStack.clear() #  = []
        

    def recalcWireList(self, nwireList, halfClkCount):

        self._prepForRecalc()

        for wireIndex in nwireList:
            # recalcOrder is a list of wire indices.  self.lastRecalcOrder
            # marks the last index into this list that we should recalculate.
            # recalcArray has entries for all wires and is used to mark
            # which wires need to be recalcualted.
            self.recalcOrderStack.push_back(wireIndex)
            self.recalcArray[wireIndex] = True
            
        self._doRecalcIterations(halfClkCount)



    cdef _doRecalcIterations(self, halfClkCount):
        # Simulation is not allowed to try more than 'stepLimit' 
        # iterations.  If it doesn't converge by then, raise an 
        # exception.
        step = 0
        stepLimit = 400
        
        while step < stepLimit:
            #print('Iter %d, num to recalc %d, %s'%(step, self.lastRecalcOrder,
            #        str(self.recalcOrder[:self.lastRecalcOrder])))

            if len(self.recalcOrderStack) == 0:
                break;


            for wireIndex in self.recalcOrderStack:
                self.newRecalcArray[wireIndex] = 0

                self._doWireRecalc(wireIndex)

                self.recalcArray[wireIndex] = False
                self.numWiresRecalculated += 1


            tmp = self.recalcArray
            self.recalcArray = self.newRecalcArray
            self.newRecalcArray = tmp

            self.recalcOrderStack = self.newRecalcOrderStack
            self.newRecalcOrderStack.clear()

            step += 1

        # The first attempt to compute the state of a chip's circuit
        # may not converge, but it's enough to settle the chip into
        # a reasonable state so that when input and clock pulses are
        # applied, the simulation will converge.
        if step >= stepLimit:
            msg = 'ERROR: Sim  did not converge after %d iterations'% \
                  ( stepLimit)
            if self.callback_addLogStr:
                self.callback_addLogStr(msg)
            # Don't raise an exception if this is the first attempt
            # to compute the state of a chip, but raise an exception if
            # the simulation doesn't converge any time other than that.
            if halfClkCount > 0:
                traceback.print_stack()
                raise RuntimeError(msg)

        # Check that we've properly reset the recalcArray.  All entries
        # should be zero in preparation for the next half clock cycle.
        # FIXME WE SHOULD REALLY DO THIS
        # Only do this sanity check for the first clock cycles.
        if halfClkCount < 20:
            needNewArray = False
            for recalc in self.recalcArray:
                if recalc != False:
                    needNewArray = True
                    if step < stepLimit:
                        msg = 'ERROR: at halfclk %d, '%(halfClkCount) + \
                              'after %d iterations'%(step) + \
                              'an entry in recalcArray is not False at the ' + \
                              'end of an update'
                        print(msg)
                        break
            if needNewArray:
                print "OMG WE NEEDED A NEW ARRAY"
                self.recalcArray = np.zeros_like(self.recalcArray) # [False] * len(self.recalcArray)
                

    cdef void _floatWire(self, int wireIndex):
        cdef int i = wireIndex
        cdef state = self._wireState[i]

        if self._wirePulled[i] == PULLED_HIGH:
            self._wireState[i] = PULLED_HIGH
        elif self._wirePulled[i] == PULLED_LOW:
            self._wireState[i] = PULLED_LOW
        else:
            if state == GROUNDED or state == PULLED_LOW:
                self._wireState[i] = FLOATING_LOW
            if state == HIGH or state == PULLED_HIGH:
                self._wireState[i] = FLOATING_HIGH


    cdef _doWireRecalc(self, wireIndex):
        if wireIndex == self.gndWireIndex or wireIndex == self.vccWireIndex:
            return
        
        group = set()

        # addWireToGroup recursively adds this wire and all wires
        # of connected transistors
        self._addWireToGroup(wireIndex, group)
        
        newValue = self._getWireValue(group)
        newHigh = newValue == HIGH or newValue == PULLED_HIGH or \
                  newValue == FLOATING_HIGH

        for groupWireIndex in group:
            if groupWireIndex == self.gndWireIndex or \
               groupWireIndex == self.vccWireIndex:
                # TODO: remove gnd and vcc from group?
                continue
            simWire = self._wireList[groupWireIndex]
            #simWire.state = newValue
            self._wireState[groupWireIndex] = newValue
            for transIndex in simWire.gateInds:
                gateState = self._transistorState[transIndex]

                if newHigh == True and gateState == NmosFet.GATE_LOW:
                    self._turnTransistorOn(transIndex)
                if newHigh == False and gateState == NmosFet.GATE_HIGH:
                    self._turnTransistorOff(transIndex)

    cdef _turnTransistorOn(self, tidx):
        self._transistorState[tidx] = NmosFet.GATE_HIGH

        wireInd = self._transistorWires[tidx, TW_S1]
        if self.newRecalcArray[wireInd] == 0:
            self.newRecalcArray[wireInd] = 1
            self.newRecalcOrderStack.push_back(wireInd)

        wireInd = self._transistorWires[tidx, TW_S2]
        if self.newRecalcArray[wireInd] == 0:
            self.newRecalcArray[wireInd] = 1
            self.newRecalcOrderStack.push_back(wireInd)

    cdef _turnTransistorOff(self, tidx):
        self._transistorState[tidx] = NmosFet.GATE_LOW

        #t = self._transistorList[tidx]
        c1Wire = self._transistorWires[tidx, TW_S1]
        c2Wire = self._transistorWires[tidx, TW_S2]
        self._floatWire(c1Wire)
        self._floatWire(c2Wire)

        wireInd = c1Wire
        if self.newRecalcArray[wireInd] == 0:
            self.newRecalcArray[wireInd] = 1
            self.newRecalcOrderStack.push_back(wireInd)

        wireInd = c2Wire
        if self.newRecalcArray[wireInd] == 0:
            self.newRecalcArray[wireInd] = 1
            self.newRecalcOrderStack.push_back(wireInd)

    cdef _getWireValue(self, group):
        """
        This function performs group resolution for a collection
        of wires

        if any wire in the group is ground, return grounded
        if any wire in the group is vcc and it's not grounded, 
        return high; else return grounded

        
        """
        # TODO PERF: why turn into a list?
        l = list(group)
        sawFl = False
        sawFh = False
        value = self._wireState[l[0]]

        for wireIndex in group:
            if wireIndex == self.gndWireIndex:
                return GROUNDED
            if wireIndex == self.vccWireIndex:
                if self.gndWireIndex in group:
                    return GROUNDED
                else:
                    return HIGH

            wire_pulled = self._wirePulled[wireIndex]
            wire_state = self._wireState[wireIndex]
            if wire_pulled == PULLED_HIGH:
                value = PULLED_HIGH
            elif wire_pulled == PULLED_LOW:
                value = PULLED_LOW
                
            if wire_state == FLOATING_LOW:
                sawFl = True
            elif wire_state == FLOATING_HIGH:
                sawFh = True

        if value == FLOATING_LOW or value == FLOATING_HIGH:
            # If two floating regions are connected together,
            # set their voltage based on whichever region has
            # the most components.  The resulting voltage should
            # be determined by the capacitance of each region.
            # Instead, we use the count of the number of components
            # in each region as an estimate of how much charge 
            # each one holds, and set the result hi or low based
            # on which region has the most components.
            if sawFl and sawFh:
                sizes = self._countWireSizes(group)
                if sizes[1] < sizes[0]:
                    value = FLOATING_LOW
                else:
                    value = FLOATING_HIGH
        return value

    cdef _addWireToGroup(self, wireIndex, group):
        self.numAddWireToGroup += 1
        group.add(wireIndex)
        wire = self._wireList[wireIndex]

        if wireIndex == self.gndWireIndex or wireIndex == self.vccWireIndex:
            return

        # for each transistor which switch other wires into connection
        # with this wire
        for t in wire.ctInds: 
            self._addWireTransistor (wireIndex, t, group)

    @cython.boundscheck(False)
    @cython.nonecheck(False)
    @cython.initializedcheck(False)
    cdef _addWireTransistor(self, wireIndex, t, group):
        # for this wire and this transistor, check if the transistor
        # is on. If it is, add the connected wires recursively
        # 
        self.numAddWireTransistor += 1
        cdef int other = -1
        #trans = self._transistorList[t]
        cdef c1Wire = self._transistorWires[t, TW_S1]
        cdef c2Wire = self._transistorWires[t, TW_S2]

        if self._transistorState[t] == NmosFet.GATE_LOW:
            return
        if c1Wire == wireIndex:
            other = c2Wire
        if c2Wire == wireIndex:
            other = c1Wire
        if other == self.vccWireIndex or other == self.gndWireIndex:
            group.add(other)
            return
        if other in group:
            return
        self._addWireToGroup(other, group)

    @cython.boundscheck(False)
    @cython.nonecheck(False)
    @cython.initializedcheck(False)
    cdef _countWireSizes(self, group):
        cdef int countFl = 0
        cdef int countFh = 0
        cdef int i = 0
        cdef int num = 0
        cdef int wire_state = 0
        for i in group:
            wire_state = self._wireState[i]
            num = self._numWires[i]
            if wire_state == FLOATING_LOW:
                countFl += num
            if wire_state == FLOATING_HIGH:
                countFh += num
        return [countFl, countFh]



