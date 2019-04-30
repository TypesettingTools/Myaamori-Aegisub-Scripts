from setuptools import setup

setup(
    name='sub-digest',
    version='0.0.1',
    py_modules=['subdigest'],
    install_requires=['ass'],
    entry_points={
        "console_scripts": ["subdigest=subdigest:main"]
    }
)
