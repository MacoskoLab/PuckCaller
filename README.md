# PuckCaller
Matlab package for image processing and base calling

## Requirement

PuckCaller needs a public toolset `bftools` for image conversion. You could download bftools at:
https://docs.openmicroscopy.org/bio-formats/5.7.1/users/comlinetools/index.html

Unzip the package and put it under your directory.

`Java` is required to run bftools.

## Run PuckCaller

For `Windows`:
1) Download PuckCaller Windows package;
1) Prepare manifest file;
2) Open Matlab;
3) Set PuckCaller script folder as current folder;
4) Open PuckCaller.m;
5) Click "Run" or "Run Section".

For `Linux`:
1) Download PuckCaller Linux package;
2) Compile matlab code (command might be different on your system):
```
	use .matlab-2019a
	mcc -m PuckCaller.m -a PuckCaller_script_folder -d PuckCaller_script_folder -o PuckCaller
```
3) Modify PuckCaller_script_folder/run_PuckCaller.sh
Add: 
```
		reuse Java-1.8 (or another version)
		manifest=$2
```
Modify:
```
		eval "\"{$PuckCaller_script_folder}\"" ${manifest}
```
4) Prepare manifest file;
5) Run PuckCaller:
```
	qsub -o logfile -l h_vmem=30g -l h_rt=10:0:0 -j y PuckCaller_script_folder/run_PuckCaller.sh matlab_path manifest_file
```

Notice: matlab_path is like '/Linux/redhat_7_x86_64/pkgs/matlab_2019a'

Notice: 
1) Check `example.manifest.txt` for manifest file format.
2) See `user_doc.txt` for detailed usage of PuckCaller. 
