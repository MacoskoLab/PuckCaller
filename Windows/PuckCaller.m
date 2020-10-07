%%%%This pipeline function assumes that we are using the large image
%%%%feature and the XY feature in Nikon images, and that files ending in
%%%%xy1 are for puck 1. We do not do stitching.

%This function is for beads with 7 J bases in two groups.

%%%%SETUP:
%1) When you are done with the code, you should make the raw data folder in
%Pucks and the InputFolder in find_roi online only via smart sync to save
%hard drive space. You should also delete the pucktmp directory.

%2) Change ImageSize to reflect something slightly smaller than the size of
%the final stitched images.

%3) Each ligation sequence and primer set will require a bunch of modifications
%to MapLocationsFun. To accommodate for this, I make a different version of MapLocationsFun for
%each ligation sequence. You have to change which version is called below.


%% Initialize
clear all
close all

%We assume that the nd2s have been exported to tiffs in the format:
%DescriptiveNametLYX, where DescriptiveName refers to one run of the microscope,  Y is a letter and X is a number, and L is the
%name of the ligation within that DescriptiveName file series.
%We convert the files to a final output format:
%Puck85 Ligation X Position AB

NumPar=20; %number of threads
EnforceBaseBalance=1; 
BaseBalanceTolerance=0.05;

NumLigations=20; %We assume that the missing ligation is Truseq-4 if you are doing 13.
NumBases=14; %This is the number of bases sequenced

ImageSize=6030; %The image registration will output images that are not all the exact same size, because of stitching. So find_roi_stack_fun crops the images a bit. We can choose this value to be something like 0.95 * the size of the images. So e.g. for 3x3 it should be 0.95*2048*(2*(2/3)+1) = 4500. For 7x7 it is 0.95*2048*(1+6*2/3)=9728. I used 10400 previously though.
XCorrBounds=[2800,3200,2800,3200]; %This is the ROI used in channel registration
RegisterColorChannels=1;
BeadZeroThreshold=1;
PixelCutoffRegistration=400;
PixelCutoffBasecalling=300;
DropBases=1;
BeadSizeCutoff=30;

%The illumina barcodes are assumed to be 13 bases long, consisting of the
%first 6 J bases and then the last 7 J bases. If the barcodes you are using
%are different, you have to change it in the bs2cs calls.

%Note that bs2cs will output the colors corresponding to each ligation in this ligation sequence, in the order specified here,
%So if you were only to do 6 ligations off primer N instead of 7, you would only need to
%remove the final element in the PrimerNLigationSequence

InverseLigationSequence=[3,1,7,6,5,4,2,10,8,14,13,12,11,9]; %Good for both 13 and 14 ligations.
%Before exporting, "N"s are added to the end of the ligation
%sequence, and must then be inserted into the correct location to stand in
%for the missing ligations. This code puts the N at position 7
WhichLigationsAreMissing=[1,2,3,4,5,6,7,8,9,10,11,12,13,14];


%% Load parameters from manifest file
[file,path] = uigetfile('*.txt', 'Select manifest file');
manifest = [path,file];

% Check if manifest file exists
if ~exist(manifest,'file')
    error('Manifest file not found');
end

% Load manifest content into a variable set
fid = fopen(manifest, 'rt');
fcon = textscan(fid,  '%s%s', 'Delimiter', '=');
fclose(fid);
indat = horzcat(fcon{:});
[m,n] = size(indat);
params = [];
for i=1:m
   params.(indat{i,1}) = indat{i,2}; 
end

% Retrieve variable values based on variable names
ScriptFolder = params.('ScriptFolder');
BftoolsFolder = params.('BftoolsFolder');
Nd2Folder = params.('Nd2Folder');
FolderWithProcessedTiffs = params.('FolderWithProcessedTiffs');
OutputFolderRoot = params.('OutputFolderRoot');
IndexFiles = params.('IndexFiles');
PuckName = params.('PuckName');
PucksToAnalyze = params.('PucksToAnalyze');
LigationToIndexFileMapping = params.('LigationToIndexFileMapping');
tnumMapping = params.('TnumMapping');
DeleteIntermediateFiles = 'false';
if isfield(params,'DeleteIntermediateFiles')
    DeleteIntermediateFiles = params.('DeleteIntermediateFiles');
end

PuckImageSubstraction = 'True';
if isfield(params,'PuckImageSubstraction')
    PuckImageSubstraction = params.('PuckImageSubstraction');
end

Monobase = 0;
if isfield(params,'Monobase')
    Monobase = textscan(params.('Monobase'),'%f','Delimiter',',');
    Monobase = transpose(horzcat(Monobase{:}));
    Monobase = logical(Monobase);
end

if Monobase==1
    BaseBalanceTolerance=0.01;
end

% Convert string to cell array and vector
IndexFiles = textscan(IndexFiles,'%s','Delimiter',',');
IndexFiles = horzcat(IndexFiles{:});
LigationToIndexFileMapping = textscan(LigationToIndexFileMapping,'%f','Delimiter',',');
LigationToIndexFileMapping = horzcat(LigationToIndexFileMapping{:});
tnumMapping = textscan(tnumMapping,'%f','Delimiter',',');
tnumMapping = horzcat(tnumMapping{:});
PucksToAnalyze = textscan(PucksToAnalyze,'%f','Delimiter',',');
PucksToAnalyze = horzcat(PucksToAnalyze{:});

BarcodeSequence=[1,2,3,4,0,5,0,6,0,7,8,9,10,11,0,12,0,13,0,14];
if isfield(params,'MissingBarcodeSequence')
    MissingBarcodeSequence = params.('MissingBarcodeSequence');
    MissingBarcodeSequence = textscan(MissingBarcodeSequence,'%f','Delimiter',',');
    MissingBarcodeSequence = horzcat(MissingBarcodeSequence{:});
    BarcodeSequence=[];
    j = 1;
    for i=1:20
        if ismember(i, MissingBarcodeSequence)
            BarcodeSequence=[BarcodeSequence;0];
        else
            BarcodeSequence=[BarcodeSequence;j];
            j = j + 1;
        end
    end
end

addpath(ScriptFolder);

% Create PuckNames from PuckName and PuckSToAnalyze
% Note that the order in PuckNames should match the order in the .nd2 file.
[m,n]=size(PucksToAnalyze);
PuckNames=string(m);
for i=1:m
    PuckNames(i)=[PuckName,'_',pad(num2str(PucksToAnalyze(i)),2,'left','0')];
end


%% Create folders
OutputFolders={};
for puck=1:length(PuckNames)
    ProcessedImageFolders{puck}=[FolderWithProcessedTiffs,PuckNames{puck},'\'];
    mkdir([FolderWithProcessedTiffs,PuckNames{puck}]);
    OutputFolders{puck}=[OutputFolderRoot,PuckNames{puck},'\'];
    mkdir(OutputFolders{puck});
    
    % Copy manifest file to output folder
    copyfile(manifest,[OutputFolders{puck},'\']);
end


%% Convert .nd2 to .tif
for pucknum=1:length(PuckNames)
    puck=PucksToAnalyze(pucknum);
    for ligation=1:NumLigations
        if BarcodeSequence(ligation)==0
            continue;
        end
        
        tnum=tnumMapping(ligation);
        filename=[Nd2Folder,IndexFiles{LigationToIndexFileMapping(ligation)},'.nd2'];
        if ~exist(filename,'file')
            display(['file',32,filename,32,'not found']);
            continue;
        end
        
        % Run showinf to check if puck and tnum are valid
        r = randi([10000000 99999999],1);
        outputfilename=[ProcessedImageFolders{pucknum},'showinf_',num2str(r),'.txt'];
        commandfile=fopen('C:\showinfCommand.cmd','w');
        fwrite(commandfile,strcat(BftoolsFolder,'showinf',32,'"',filename,'"',32,'>',32,outputfilename));
        fclose(commandfile);
        !C:/showinfCommand
        text = fileread(outputfilename);
        text = regexp(text, '\n', 'split');
        IdxSeriesCount = find(contains(text,'Series count ='));
        IdxSizeT = find(contains(text,'SizeT ='));
        IdxSizeT = IdxSizeT(1);
        SeriesCount = split(text(IdxSeriesCount),'=');
        SizeT= split(text(IdxSizeT),'=');
        SeriesCount = strtrim(SeriesCount(2));
        SizeT= strtrim(SizeT(2));
        SeriesCount = str2num(SeriesCount{1});
        SizeT = str2num(SizeT{1});
        
        if puck > SeriesCount
            display('puck is invalid');
            continue;
        end
        if tnum > SizeT
            display('tnum is invalid');
            continue;
        end
        delete(outputfilename);
        
        % Convert .nd2 to .tiff
        outputfilename=[ProcessedImageFolders{pucknum},PuckNames{pucknum},'_Ligation_',pad(num2str(ligation),2,'left','0'),'_Stitched.tif'];
        commandfile=fopen('C:\bfconvertCommand.cmd','w');
        fwrite(commandfile,strcat(BftoolsFolder,'bfconvert -tilex 512 -tiley 512 -series',32,num2str(puck-1),' -timepoint',32,num2str(tnum-1),' "',replace(filename,'\','\\'),'" "',replace(outputfilename,'\','\\'),'"'));
        fclose(commandfile);
        !C:/bfconvertCommand
    end
end


%% Registration
for puck=1:length(PuckNames)
    display(['Beginning registration on puck number ',num2str(puck)])
    BaseName=[ProcessedImageFolders{puck},PuckNames{puck},'_Ligation_'];
    Suffix='_Stitched';
    find_roi_stack_fun_LMC(BaseName,Suffix,ImageSize,'PixelCutoff',PixelCutoffRegistration,'XCorrBounds',XCorrBounds,'RegisterColorChannels',1,'NumPar',NumPar,'BeadseqCodePath',ScriptFolder,'BarcodeSequence',BarcodeSequence);
	%The outputted files are of the form 
	%[BaseName,int2str(mm),' channel ',int2str(k),suffix,' transform.tif']
end


%% Bead calling and sequencing
for puck=1:length(PuckNames)
    BaseName=[ProcessedImageFolders{puck},PuckNames{puck},'_Ligation_'];
    suffix='_Stitched';
    disp(['Beginning basecalling for puck number ',num2str(puck)])
	[Bead BeadImage]=BeadSeqFun6_FC(BaseName,suffix,OutputFolders{puck},BeadZeroThreshold,BarcodeSequence,NumPar,NumLigations,PuckNames{puck},EnforceBaseBalance,BaseBalanceTolerance,'PixelCutoff',PixelCutoffBasecalling,'DropBases',DropBases,'BeadSizeThreshold',BeadSizeCutoff,'PuckImageSubstraction',PuckImageSubstraction);
	
	BeadBarcodes = [Bead.Barcodes];
    BeadLocations = {Bead.Locations};
    [UniqueBeadBarcodes,BBFirstRef,BBOccCounts]=unique(BeadBarcodes, 'stable');
    [~, b] = ismember(BeadBarcodes, BeadBarcodes(BBFirstRef(accumarray(BBOccCounts,1)>1)));
    UniqueBeadBarcodes2 = BeadBarcodes(b<1);
    UniqueBeadLocations = BeadLocations(b<1);
    BaseBalanceBarcodes=[UniqueBeadBarcodes2];
    BaseBalanceBase5Barcodes=cellfun(@(x) reverse(string(x)),{dec2base(BaseBalanceBarcodes,5,NumBases)},'UniformOutput',false);
    BaseBalanceBase5Barcodes=BaseBalanceBase5Barcodes{1};
    UniqueBeadBarcodesForExport=char(replace(BaseBalanceBase5Barcodes,{'0','1','2','3','4'},{'N','T','G','C','A'}));
    if NumBases<14 %This is to deal with the InverseLigationSequence -- the export barcodes have to be 14 bases long
        UniqueBeadBarcodesForExport(:,NumBases+1:14)='N';
        UniqueBeadBarcodesForExport=UniqueBeadBarcodesForExport(:,WhichLigationsAreMissing);
    end
    file=fullfile(OutputFolders{puck},'BeadBarcodes.txt');
    dlmwrite(file,[UniqueBeadBarcodesForExport]);
    file=fullfile(OutputFolders{puck},'BeadLocations.txt');
    dlmwrite(file,[UniqueBeadLocations]);
end


%% Delete intermediate files
if lower(DeleteIntermediateFiles)~="false"
	for puck=1:length(PuckNames)
		rmdir(ProcessedImageFolders{puck}, 's');
	end
end

