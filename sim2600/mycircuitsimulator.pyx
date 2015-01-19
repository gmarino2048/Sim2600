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

cpdef enum WireState:
    PULLED_HIGH  = 1 << 0
    PULLED_LOW     = 1 << 1
    GROUNDED       = 1 << 2
    HIGH           = 1 << 3
    FLOATING_HIGH  = 1 << 4
    FLOATING_LOW   = 1 << 5
    FLOATING       = 1 << 6

cdef class Wire:

    cdef int index
    cdef char * name
    cdef object ctInds
    cdef object gateInds
    cdef int pulled
    cdef WireState state

    def __init__(self, idIndex, name, controlTransIndices, transGateIndices, pulled):
        self.index = idIndex
        self.name = name

        # Transistors that switch other wires into connection with this wire
        self.ctInds = controlTransIndices

        # Transistors whos gate is driven by this wire
        self.gateInds = transGateIndices

        # pulled reflects whether or not the wire is connected to
        # a pullup or pulldown.
        self.pulled = pulled

        # state reflects the logical state of the wire as the 
        # simulation progresses.
        self.state = pulled

    def __repr__(self):
        rstr = 'Wire %d "%s": %d  ct %s gates %s'%(self.idIndex, self.name,
               self.state, str(self.ctInds), str(self.gateInds))
        return rstr

    def setHigh(self):
        """ Used to pin a pad or external input high """
        self.pulled = PULLED_HIGH
        self.state  = PULLED_HIGH

    def setLow(self):
        """ Used to pin a pad or external input low """
        self.pulled = PULLED_LOW
        self.state  = PULLED_LOW

    def setPulledHighOrLow(self, boolHigh):
        """ Used to pin a pad or external input high or low """
        if boolHigh == True:
            self.pulled = PULLED_HIGH
            self.state  = PULLED_HIGH
        elif boolHigh == False:
            self.pulled = PULLED_LOW
            self.state  = PULLED_LOW
        else:
            raise Exception('Arg to setPulledHighOrLow is not True or False')

    def isHigh(self):
        if self.state == FLOATING_HIGH or \
           self.state == PULLED_HIGH or \
           self.state == HIGH:
            return True
        return False
        
    def isLow(self):
        if self.state == FLOATING_LOW or \
           self.state == PULLED_LOW or \
           self.state == GROUNDED:
            return True
        return False

    property gateInds:
        def __get__(self):
            return self.gateInds

    property ctInds:
        def __get__(self):
            return self.ctInds

    property state:
        def __get__(self):
            return self.state
        def __set__(self, v):
            self.state = v

    property pulled:
        def __get__(self):
            return self.pulled

class NmosFet:
    GATE_LOW  = 0
    GATE_HIGH = 1 << 0

    def __init__(self, idIndex, side1WireIndex, side2WireIndex, gateWireIndex):
        
        # Wires switched together when this transistor is on
        self.side1WireIndex = side1WireIndex
        self.side2WireIndex = side2WireIndex
        self.gateWireIndex  = gateWireIndex

        self.gateState = NmosFet.GATE_LOW
        self.index = idIndex

    def __repr__(self):
        rstr = 'NFET %d: %d gate %d [%d, %d]'%(self.index, self.state,
               self.gateWireIndex, self.size1WireIndex, self.side2WireIndex)
        return rstr



class CircuitSimulator(object):
    def __init__(self):
        self.name = ''
        self.wireList = None        # wireList[i] is a Wire.  wireList[i].index = i
        self.transistorList = None
        self.wireNames = dict()     # key is string wire names, value is integer wire index
        self.halfClkCount = 0       # the number of half clock cycles (low to high or high to low)
                                    # that the simulation has run

        self.recalcArray = None

        # Performance / diagnostic info as sim progresses
        self.numAddWireToGroup = 0
        self.numAddWireTransistor = 0
        # General sense of how much work it's doing
        self.numWiresRecalculated = 0
        
        # If not None, call this to add a line to some log
        self.callback_addLogStr = None   # callback_addLogStr ('some text')

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
        for ind, wire in enumerate(self.wireList):
            if wire != None:
                wireInds.append(ind)
        self.recalcWireList (wireInds)
        
    def prepForRecalc(self):
        if self.recalcArray == None:
            self.recalcCap = len(self.transistorList)
            # Using lists [] for these is faster than using array('B'/'L', ...)
            self.recalcArray = np.zeros(self.recalcCap, dtype=np.uint8) # [False] * self.recalcCap
            self.recalcOrderStack = []
            self.newRecalcArray = np.zeros(self.recalcCap, dtype=np.uint8) # [0] * self.recalcCap
            self.newRecalcOrderStack = []
        
    def recalcWireList(self, nwireList):
        self.prepForRecalc()

        for wireIndex in nwireList:
            # recalcOrder is a list of wire indices.  self.lastRecalcOrder
            # marks the last index into this list that we should recalculate.
            # recalcArray has entries for all wires and is used to mark
            # which wires need to be recalcualted.
            self.recalcOrderStack.append(wireIndex)
            self.recalcArray[wireIndex] = True
            
        self.doRecalcIterations()

    def recalcWire(self, wireIndex):
        self.prepForRecalc()

        self.recalcOrderStack.append(wireIndex)
        self.recalcArray[wireIndex] = True

        self.doRecalcIterations()

    def doRecalcIterations(self):
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

                self.doWireRecalc(wireIndex)

                self.recalcArray[wireIndex] = False
                self.numWiresRecalculated += 1


            tmp = self.recalcArray
            self.recalcArray = self.newRecalcArray
            self.newRecalcArray = tmp

            self.recalcOrderStack = self.newRecalcOrderStack
            self.newRecalcOrderStack = []

            step += 1

        # The first attempt to compute the state of a chip's circuit
        # may not converge, but it's enough to settle the chip into
        # a reasonable state so that when input and clock pulses are
        # applied, the simulation will converge.
        if step >= stepLimit:
            msg = 'ERROR: Sim "%s" did not converge after %d iterations'% \
                  (self.name, stepLimit)
            if self.callback_addLogStr:
                self.callback_addLogStr(msg)
            # Don't raise an exception if this is the first attempt
            # to compute the state of a chip, but raise an exception if
            # the simulation doesn't converge any time other than that.
            if self.halfClkCount > 0:
                traceback.print_stack()
                raise RuntimeError(msg)

        # Check that we've properly reset the recalcArray.  All entries
        # should be zero in preparation for the next half clock cycle.
        # Only do this sanity check for the first clock cycles.
        if self.halfClkCount < 20:
            needNewArray = False
            for recalc in self.recalcArray:
                if recalc != False:
                    needNewArray = True
                    if step < stepLimit:
                        msg = 'ERROR: at halfclk %d, '%(self.halfClkCount) + \
                              'after %d iterations'%(step) + \
                              'an entry in recalcArray is not False at the ' + \
                              'end of an update'
                        print(msg)
                        break
            if needNewArray:
                self.recalcArray = np.zeros_like(self.recalcArray) # [False] * len(self.recalcArray)

    def floatWire(self, n):
        wire = self.wireList[n]

        if wire.pulled == PULLED_HIGH:
            wire.state = PULLED_HIGH
        elif wire.pulled == PULLED_LOW:
            wire.state = PULLED_LOW
        else:
            state = wire.state
            if state == GROUNDED or state == PULLED_LOW:
                wire.state = FLOATING_LOW
            if state == HIGH or state == PULLED_HIGH:
                wire.state = FLOATING_HIGH

    # setHighWN() and setLowWN() do not trigger an update
    # of the simulation.
    def setHighWN(self, n):
        if n in self.wireNames:
            wireIndex = self.wireNames[n]
            self.wireList[wireIndex].setHigh()
            return

        assert type(n) == type(1), 'wire thing %s'%str(n)
        wire = self.wireList[n]
        if wire != None:
            wire.setHigh()
        else:
            print 'ERROR - trying to set wire None high'

    def setLowWN(self, n):
        if n in self.wireNames:
            wireIndex = self.wireNames[n]
            self.wireList[wireIndex].setLow()
            return

        assert type(n) == type(1), 'wire thing %s'%str(n)
        wire = self.wireList[n]
        if wire != None:
            wire.setLow()
        else:
            print 'ERROR - trying to set wire None low'

    def setHigh(self, wireIndex):
        self.wireList[wireIndex].setPulledHighOrLow(True)

    def setLow(self, wireIndex):
        self.wireList[wireIndex].setPulledHighOrLow(False)

    def setPulled(self, wireIndex, boolHighOrLow):
        self.wireList[wireIndex].setPulledHighOrLow(boolHighOrLow)
                
    def setPulledHigh(self, wireIndex):
        self.wireList[wireIndex].setPulledHighOrLow(True)

    def setPulledLow(self, wireIndex):
        self.wireList[wireIndex].setPulledHighOrLow(False)
        
    def isHigh(self, wireIndex):
        return self.wireList[wireIndex].isHigh()

    def isLow(self, wireIndex):
        return self.wireList[wireIndex].isLow()

    def isHighWN(self, n):
        if n in self.wireNames:
            wireIndex = self.wireNames[n]
            return self.wireList[wireIndex].isHigh()

        assert type(n) == type(1), 'ERROR: if arg to isHigh is not in ' + \
            'wireNames, it had better be an integer'
        wire = self.wireList[n]
        assert wire != None
        return wire.isHigh()
        
    def isLowWN(self, n):
        if n in self.wireNames:
            wireIndex = self.wireNames[n]
            return self.wireList[wireIndex].isLow()

        wire = self.wireList[n]
        assert wire != None
        return wire.isLow()

    # TODO: rename to getNamedSignal (name, lowBitNum, highBitNum) ('DB',0,7) 
    # TODO: elim or use wire indices
    # Use for debug and to examine busses.  This is slow. 
    def getGen(self, strSigName, size):
        data = 0
        for i in xrange(size, -1, -1):
            data = data * 2
            bit = '%s%d'%(strSigName,i)
            if self.isHighWN(bit):
                data = data + 1
        return data

    def setGen(self, data, string, size):
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
                self.wireList[k].name = name
                self.wireNames[name] = k
                i += 1

    def getWiresState(self):
        return [w.state for w in self.wireList]

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

        self.wireList = [None] * numWires

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
                self.wireList[i] = None
            else:
                self.wireList[i] = Wire(i, wireNames[i], controlFets, gates, wirePulled[i])
                self.wireNames[wireNames[i]] = i
            i += 1

        self.transistorList = [None] * numFets
        i = 0
        while i < numFets:
            s1 = fetSide1WireInds[i]
            s2 = fetSide2WireInds[i]
            gate = fetGateWireInds[i]
            
            if s1 == noWire:
                assert s2 == noWire
                assert gate == noWire
            else:
                self.transistorList[i] = NmosFet(i, s1, s2, gate)
            i += 1

        assert 'VCC' in self.wireNames
        assert 'VSS' in self.wireNames
        self.vccWireIndex = self.wireNames['VCC']
        self.gndWireIndex = self.wireNames['VSS']
        self.wireList[self.vccWireIndex].state = HIGH
        self.wireList[self.gndWireIndex].state = GROUNDED
        for transInd in self.wireList[self.vccWireIndex].gateInds:
            self.transistorList[transInd].gateState = NmosFet.GATE_HIGH

        self.lastWireGroupState = [-1] * numWires

        return rootObj

    def writeCktFile(self, filePath):
 
        rootObj = dict()
        
        numWires = len(self.wireList)
        nextCtrl = 0xFFFE

        # 'B' for unsigned integer, minimum of 1 byte
        wirePulled = array('B', [0] * numWires)

        # 'I' for unsigned int, minimum of 2 bytes
        wireControlFets = array('I')
        wireGates = array('I')
        numNoneWires = 0
        wireNames = []

        for i, wire in enumerate(self.wireList):
            if wire == None:
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
        numFets = len(self.transistorList)
        fetSide1WireInds = array('I', [noWire] * numFets)
        fetSide2WireInds = array('I', [noWire] * numFets)
        fetGateWireInds  = array('I', [noWire] * numFets)

        for i, trans in enumerate(self.transistorList):
            if trans == None:
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

    def doWireRecalc(self, wireIndex):
        if wireIndex == self.gndWireIndex or wireIndex == self.vccWireIndex:
            return

        group = set()
        self.addWireToGroup(wireIndex, group)
        
        newValue = self.getWireValue(group)
        newHigh = newValue == HIGH or newValue == PULLED_HIGH or \
                  newValue == FLOATING_HIGH

        for groupWireIndex in group:
            if groupWireIndex == self.gndWireIndex or \
               groupWireIndex == self.vccWireIndex:
                # TODO: remove gnd and vcc from group?
                continue
            simWire = self.wireList[groupWireIndex]
            simWire.state = newValue
            for transIndex in simWire.gateInds:

                t = self.transistorList[transIndex]

                if newHigh == True and t.gateState == NmosFet.GATE_LOW:
                    self.turnTransistorOn(t)
                if newHigh == False and t.gateState == NmosFet.GATE_HIGH:
                    self.turnTransistorOff(t)

    def turnTransistorOn(self, t):
        t.gateState = NmosFet.GATE_HIGH

        wireInd = t.side1WireIndex
        if self.newRecalcArray[wireInd] == 0:
            self.newRecalcArray[wireInd] = 1
            self.newRecalcOrderStack.append(wireInd)

        wireInd = t.side2WireIndex
        if self.newRecalcArray[wireInd] == 0:
            self.newRecalcArray[wireInd] = 1
            self.newRecalcOrderStack.append(wireInd)

    def turnTransistorOff(self, t):
        t.gateState = NmosFet.GATE_LOW

        c1Wire = t.side1WireIndex
        c2Wire = t.side2WireIndex
        self.floatWire(c1Wire)
        self.floatWire(c2Wire)

        wireInd = c1Wire
        if self.newRecalcArray[wireInd] == 0:
            self.newRecalcArray[wireInd] = 1
            self.newRecalcOrderStack.append(wireInd)

        wireInd = c2Wire
        if self.newRecalcArray[wireInd] == 0:
            self.newRecalcArray[wireInd] = 1
            self.newRecalcOrderStack.append(wireInd)

    def getWireValue(self, group):
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
        value = self.wireList[l[0]].state

        for wireIndex in group:
            if wireIndex == self.gndWireIndex:
                return GROUNDED
            if wireIndex == self.vccWireIndex:
                if self.gndWireIndex in group:
                    return GROUNDED
                else:
                    return HIGH
            wire = self.wireList[wireIndex]
            if wire.pulled == PULLED_HIGH:
                value = PULLED_HIGH
            elif wire.pulled == PULLED_LOW:
                value = PULLED_LOW
                
            if wire.state == FLOATING_LOW:
                sawFl = True
            elif wire.state == FLOATING_HIGH:
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
                sizes = self.countWireSizes(group)
                if sizes[1] < sizes[0]:
                    value = FLOATING_LOW
                else:
                    value = FLOATING_HIGH
        return value

    def addWireToGroup(self, wireIndex, group):
        self.numAddWireToGroup += 1
        group.add(wireIndex)
        wire = self.wireList[wireIndex]
        if wireIndex == self.gndWireIndex or wireIndex == self.vccWireIndex:
            return
        for t in wire.ctInds:
            self.addWireTransistor (wireIndex, t, group)

    def addWireTransistor(self, wireIndex, t, group):
        self.numAddWireTransistor += 1
        other = -1
        trans = self.transistorList[t]
        if trans.gateState == NmosFet.GATE_LOW:
            return
        if trans.side1WireIndex == wireIndex:
            other = trans.side2WireIndex
        if trans.side2WireIndex == wireIndex:
            other = trans.side1WireIndex
        if other == self.vccWireIndex or other == self.gndWireIndex:
            group.add(other)
            return
        if other in group:
            return
        self.addWireToGroup(other, group)


    def countWireSizes(self, group):
        countFl = 0
        countFh = 0
        for i in group:
            wire = self.wireList[i]
            num = len(wire.ctInds) + len(wire.gateInds)
            if wire.state == FLOATING_LOW:
                countFl += num
            if wire.state == FLOATING_HIGH:
                countFh += num
        return [countFl, countFh]

