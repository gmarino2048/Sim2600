#!/usr/bin/python

import os
import sys
import sqlite3

class DatabaseManager:

    TRANSISTOR_TABLE = 'transistors'
    WIRE_TABLE = 'wires'

    CREATE_TABLE = 'CREATE TABLE %s%s'

    WIRE_TABLE_DEF = '(idx INT, halfclock INT, name TEXT, state INT, pulled INT)'
    WIRE_INSERT = 'INSERT INTO %s VALUES (?,?,?,?,?)' % (WIRE_TABLE,)

    TRANS_TABLE_DEF = '(idx INT, halfclock INT, state INT, side1WireIndexI INT, side2WireIndex INT, gateWireIndex INT)'
    TRANS_INSERT = 'INSERT INTO %s VALUES (?,?,?,?,?,?)' % (TRANSISTOR_TABLE,)

    def __init__(self, filename):
        self.filename = filename
        if os.path.exists(self.filename):
            confirmation = ''
            while confirmation != 'y' and confirmation != 'n':
                confirmation = raw_input('Database file already exists. Overwrite? (y/n)')

            if confirmation == 'y':
                os.remove(filename)
            else:
                raise ValueError('File already exists, try again with a different filename')
        
        self.connection = sqlite3.connect(self.filename)
        self.cursor = self.connection.cursor()

        self._initdb()


    def __del__(self):
        '''Close the database connection when this object goes out of scope'''
        try:
            self.connection.close()
        except AttributeError:
            pass

    
    def _initdb(self):
        '''Initialize the database to store the transistor and wire info'''
        # First create the initial tables
        create_wires = self.CREATE_TABLE % (self.WIRE_TABLE, self.WIRE_TABLE_DEF)
        create_trans = self.CREATE_TABLE % (self.TRANSISTOR_TABLE, self.TRANS_TABLE_DEF)
        
        self.cursor.execute(create_wires)
        self.cursor.execute(create_trans)

        self.connection.commit()


    def _commit_wires(self, halfclock, wires):
        '''Commit all wires to the database'''
        wire_tups = []
        for wire in wires:
            tup = (
                wire.index,
                halfclock,
                wire.name,
                wire.state,
                wire.pulled
            )
            wire_tups.append(tup)

        self.cursor.executemany(self.WIRE_INSERT, wire_tups)


    def _commit_transistors(self, halfclock, transistors):
        '''Commit all transistors to the database'''
        trans_tups = []
        for transistor in transistors:
            tup = (
                transistor.index,
                halfclock,
                transistor.gateState,
                transistor.side1WireIndex,
                transistor.side2WireIndex,
                transistor.gateWireIndex
            )
            trans_tups.append(tup)
        
        self.cursor.executemany(self.TRANS_INSERT, trans_tups)


    def commit(self, halfclock, wires, transistors):
        '''Commit all wires and transistors to the database'''
        self._commit_wires(halfclock, wires)
        self._commit_transistors(halfclock, transistors)

        self.connection.commit()
