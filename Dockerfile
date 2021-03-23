FROM ubuntu:xenial

RUN DEBIAN_FRONTEND=noninteractive apt update
RUN DEBIAN_FRONTEND=noninteractive apt -y upgrade
RUN DEBIAN_FRONTEND=noninteractive apt -y install \
    build-essential \
    freeglut3 \
    freeglut3-dev \
    python \
    python-dev \
    python-numpy \
    python-pip \
    python-pil \
    python-wheel \
    python-setuptools

RUN pip install Cython==0.23.4
RUN pip install PyOpenGL
RUN pip install Pillow
