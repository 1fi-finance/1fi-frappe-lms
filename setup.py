from setuptools import setup, find_packages
import os

# get version from __version__ variable in lending/__init__.py
from lending import __version__ as version

install_requires = []
requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
if os.path.exists(requirements_path):
	with open(requirements_path) as f:
		install_requires = [
			line.strip() for line in f
			if line.strip() and not line.strip().startswith("#")
		]

setup(
	name="lending",
	version=version,
	description="Lending",
	author="Frappe",
	author_email="contact@frappe.io",
	packages=find_packages(),
	zip_safe=False,
	include_package_data=True,
	install_requires=install_requires,
)
