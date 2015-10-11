from distutils.core import setup
from Cython.Build import cythonize
import numpy as np

setup(name='sim2600',
      version='0.1',
      description='Simulation of Atari 2600', 
      author='Greg Jones',
      packages=['sim2600'],
      include_dirs=[np.get_include()], 
      ext_modules = cythonize("sim2600/mycircuitsimulator.pyx", 
                              language='c++'), 
      package_data={'sim2600': ['chips/*', 'roms/*']},
     )


