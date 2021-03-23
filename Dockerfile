FROM ubuntu:xenial

RUN DEBIAN_FRONTEND=noninteractive apt update
RUN DEBIAN_FRONTEND=noninteractive apt upgrade
RUN DEBIAN_FRONTEND=noninteractive apt install \
    build-essential \
    freeglut3 \
    freeglut3-dev \
    python \
    python-dev \
    python-pip \
    python-pil \
    python-wheel \
    python-setuptools

RUN pip install pil
RUN pip install pillow
