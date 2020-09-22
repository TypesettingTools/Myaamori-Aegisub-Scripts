from setuptools import setup

setup(
    name='fontvalidator',
    version='0.0.1',
    py_modules=['fontvalidator'],
    install_requires=['ass', 'fonttools', 'ebmlite'],
    entry_points={
        "console_scripts": ["fontvalidator=fontvalidator:main"]
    }
)
