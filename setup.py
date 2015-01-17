from distutils.core import setup

setup(name='sim2600',
      version='0.1',
      description='Simulation of Atari 2600', 
      author='Greg Jones',
      packages=['sim2600'],
      package_data={'sim2600': ['chips/*', 'roms/*']},
     )


