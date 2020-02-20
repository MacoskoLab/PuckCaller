function [Bead BeadImage]=BeadSeqFun6_FC(BaseName, suffix, OutputFolder,BeadZeroThreshold,BarcodeSequence,NumPar,NumLigations,PuckName,EnforceBaseBalance,BaseBalanceTolerance,varargin)
%in addition to its outputs, the function will write images of the
%basecalls and of the microscope images to the OutputFolder directory


%clear all
%close all

%Currently, backgroundthreshold is determined *manually* from the images.
%This should be the average intensity of the dark pixels *between beads*.
%For the confocal 150 is usually good. Thanks, Marvin.

    PixelThreshold=30; %changed to 200 from 150
    index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="PixelCutoff"), varargin, 'UniformOutput', 1));
    if ~isempty(index)
        PixelThreshold=varargin{index+1};
    end
    DropBases=1;
    index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="DropBases"), varargin, 'UniformOutput', 1));
    if ~isempty(index)
        DropBases=varargin{index+1};
    end

    BeadSizeThreshold=30;
    index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="BeadSizeThreshold"), varargin, 'UniformOutput', 1));
    if ~isempty(index)
        BeadSizeThreshold=varargin{index+1};
    end
    
    PuckImageSubstraction='True';
    index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="PuckImageSubstraction"), varargin, 'UniformOutput', 1));
    if ~isempty(index)
        PuckImageSubstraction=varargin{index+1};
    end
    
starttime=tic();

calibrate=1;
calibratechannels=[1,2]; %typically these should be successive, and calibratechannels(1) should be odd, so you're looking at a first and second ligation
numchannels=4; %4 channels is hardcoded
%While we were using CIP, the correct factor here was 0.5
Cy3TxRMixing=0.5; %we subtract this factor *Cy3 Z score from TxR Z score. NOTE: This is empirical! If you change parameters you have to change this.
PreviousRoundMixing=0.4; %we subtract this factor *the previous round's Z scores from the current round's Z scores on Even ligations only
loverride=0; %This is the maximum value of l to use when processing the barcodes. If loverride=0, we just use l.


%At the moment we use all 20 ligations for the analysis, but this might not
%be necessary.


% l=0;
% while true
%     if exist([BaseName,pad(num2str(l+1),2,'left','0'),' channel ',int2str(1),suffix,' transform.tif'],'file')
%         l=l+1;
%     else
%         break
%     end
% end

[m,n]=size(BarcodeSequence);
l=0;
starti=-1;
for k=1:m
    if BarcodeSequence(k)==0
        l=l+1;
        continue
    end
    if starti<0
       starti=k;
    end
    if exist([BaseName,pad(num2str(l+1),2,'left','0'),suffix,'.tif'],'file')
        l=l+1;
    else
        break
    end
end

info=imfinfo([BaseName,pad(num2str(starti),2,'left','0'),' channel ',int2str(1),suffix,' transform.tif']);

%FOR DEBUGGING: Reduce the size of the area to be analyzed here
ROI=[[1,info.Height];[1,info.Width]];

ROIHeight=ROI(1,2)-ROI(1,1)+1;
ROIWidth=ROI(2,2)-ROI(2,1)+1;

%puckimagefull=zeros(info.Height,info.Width,numchannels);
puckimage=zeros(ROIHeight,ROIWidth,numchannels);
pixelvals=zeros(ROIHeight*ROIWidth,numchannels);
puckzscores=zeros(ROIHeight,ROIWidth,numchannels);
PreviousRoundZScores=zeros(ROIHeight,ROIWidth,numchannels);
%maxpixelvals=zeros(ROIHeight*ROIWidth,l);
CertaintyMap=zeros(ROIHeight,ROIWidth,l);
MaxOfPuckImage=zeros(ROIHeight,ROIWidth,l);

pixelvalplot=zeros(NumLigations,4);
pixelzscoreplot=zeros(NumLigations,4);

if loverride>0
    l=loverride;
end

%% Loading in the data and calling the bases
for m=1:NumLigations
%    m

    if BarcodeSequence(m)==0
        if mod(m,2)==1
            PreviousRoundCalls=-1;
        end
        continue
    end

    for k=1:4
        puckimage(:,:,k)=imread([BaseName,pad(num2str(m),2,'left','0'),' channel ',int2str(k),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)});
    end
    
     unsubtracted =  puckimage;
     for k = 1:4
          tempimage = puckimage(:,:,k);
            
                SE =  strel('ball',50,30);
                J = imtophat(tempimage,SE) ;  
                 puckimage(:,:,k) = J;
     end

     channel3 = puckimage(:,:,3);
     channel2 = puckimage(:,:,2);
     
     threshidx = find(channel2>10000);
     scatter(channel2(threshidx), channel3(threshidx));
     p = polyfit(channel2(threshidx),channel3(threshidx),1);
    puckimage(:,:,3)=(puckimage(:,:,3)-Cy3TxRMixing*puckimage(:,:,2));
    if m == 9 || m==10
    1
    end
    
    if mod(m,2)==1
        PreviousRoundImage=puckimage;
    else
        SubtractLastRound=(max(puckimage,[],3)./sum(puckimage,3)<0.8); %We only subtract out the last round's Z scores if there are other Z scores that are reasonably large compared to the brightest
        for k=1:4 %this is ugly, but I couldn't work out a better way to do it
                      
            mask = PreviousRoundCalls == k;
            if lower(char(PuckImageSubstraction))=="true"
                puckimage(:,:,k)=puckimage(:,:,k)-mask.*PreviousRoundMixing.*(puckimage(:,:,k));
            end
 
        end        
    end

    Counter=0;
    if EnforceBaseBalance && BarcodeSequence(m)~=0
        multiplier=[1 1 1 1];
        TestImage=puckimage((round(ROIHeight/2)-500):(round(ROIHeight/2)+500),(round(ROIWidth/2)-500):(round(ROIWidth/2)+500),:);
        
        
        while true
            Counter=Counter+1;
            if Counter>1000
                disp(['Terminating Base Balance Enforcement for Ligation ',num2str(m),' -- base balance was not obtained.'])
                break
            end
            for j=1:4
                tmppuckimage(:,:,j)=multiplier(j)*TestImage(:,:,j);
            end
            [TestM,TestI]=max(tmppuckimage,[],3); %I is the matrix of indices.    
            TestI(TestM<PixelThreshold)=0; %This is the z score threshold -- z scores less than ZScoreThreshold are treated as 0.
            for j=1:4
                BaseBalance(j)=nnz(TestI==j);
            end
            if (max(BaseBalance)-min(BaseBalance))/sum(BaseBalance)>BaseBalanceTolerance
                multiplier(BaseBalance==min(BaseBalance))=multiplier(BaseBalance==min(BaseBalance))+0.05;
            else
                disp(['Terminating Base Balance Enforcement for Ligation ',num2str(m),' after ',num2str(Counter-1),' adjustments.'])
                multiplier
                break
            end
        end
        for j=1:4
            puckimage(:,:,j)=multiplier(j)*puckimage(:,:,j);
        end
    end
    

        
    [M,I]=max(puckimage,[],3); %I is the matrix of indices.

    I(M<PixelThreshold)=0; %This is the z score threshold -- z scores less than ZScoreThreshold are treated as 0.
    Indices(:,:,m)=uint8(I);
    
    if mod(m,2)==1
        PreviousRoundCalls=Indices(:,:,m);
    end
    
%    if m==2 %to look at phasing, we want to see the correlation between the previous round's call and this round's call. So we 
%        figure(8)
%        heatmap(reshape(Indices(:,:,1:2),ROIHeight*ROIWidth,2))
%    end

    %NOTE: This does not account for 1) knowledge of the previous base or
    %2) certainty, which can be incorporated based on the distance between
    %the two highest Z scores, or the Z score of the Z score, i.e. how much
    %higher the max Z score is than the other Z scores.
    
    
end

%% Show a plot of the pixel z scores for the pixel that is chosen in the previous section
if 0
    b=bar(pixelzscoreplot);
    b(1).FaceColor='b';
    b(2).FaceColor='g';
    b(3).FaceColor='y';
    b(4).FaceColor='r';
    
    b=bar(pixelvalplot);
    b(1).FaceColor='b';
    b(2).FaceColor='g';
    b(3).FaceColor='y';
    b(4).FaceColor='r';
    
    
end


%% Output images of the base calls:
if 1
%    OutputFolder='C:\Users\Sam\Dropbox (MIT)\Project - SlideSeq\BeadSeq Code\find_roi\InputFolder-Puck85-170818\Position A1 Base Calls - Params 7\';
    %NOTE: if you are in matlab and you try to write a binary image as a
    %tiff, imagej won't be able to open it for some weird reason.
    imwrite(256*uint16(Indices(:,:,1)==1),[OutputFolder,'Channel1Calls.tiff']);
    imwrite(256*uint16(Indices(:,:,1)==2),[OutputFolder,'Channel2Calls.tiff']);
    imwrite(256*uint16(Indices(:,:,1)==3),[OutputFolder,'Channel3Calls.tiff']);
    imwrite(256*uint16(Indices(:,:,1)==4),[OutputFolder,'Channel4Calls.tiff']);
    for jm = 2:size(Indices,3)
        imwrite(256*uint16(Indices(:,:,jm)==1),[OutputFolder,'Channel1Calls.tiff'],'WriteMode','append');
        imwrite(256*uint16(Indices(:,:,jm)==2),[OutputFolder,'Channel2Calls.tiff'],'WriteMode','append');
        imwrite(256*uint16(Indices(:,:,jm)==3),[OutputFolder,'Channel3Calls.tiff'],'WriteMode','append');
        imwrite(256*uint16(Indices(:,:,jm)==4),[OutputFolder,'Channel4Calls.tiff'],'WriteMode','append');
    end

    if 0 %this is currently not executed because the maximum tiff file size is exceeded
    imwrite(imread([BaseName,pad(num2str(1),2,'left','0'),' channel ',int2str(1),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)}),[OutputFolder,'Channel1Image.tiff']);
    imwrite(imread([BaseName,pad(num2str(1),2,'left','0'),' channel ',int2str(2),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)}),[OutputFolder,'Channel2Image.tiff']);
    imwrite(imread([BaseName,pad(num2str(1),2,'left','0'),' channel ',int2str(3),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)}),[OutputFolder,'Channel3Image.tiff']);
    imwrite(imread([BaseName,pad(num2str(1),2,'left','0'),' channel ',int2str(4),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)}),[OutputFolder,'Channel4Image.tiff']);
    pause(2);
    for jm = 2:size(Indices,3)
        imwrite(imread([BaseName,pad(num2str(jm),2,'left','0'),' channel ',int2str(1),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)}),[OutputFolder,'Channel1Image.tiff'],'WriteMode','append');
        imwrite(imread([BaseName,pad(num2str(jm),2,'left','0'),' channel ',int2str(2),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)}),[OutputFolder,'Channel2Image.tiff'],'WriteMode','append');
        imwrite(imread([BaseName,pad(num2str(jm),2,'left','0'),' channel ',int2str(3),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)}),[OutputFolder,'Channel3Image.tiff'],'WriteMode','append');
        imwrite(imread([BaseName,pad(num2str(jm),2,'left','0'),' channel ',int2str(4),suffix,' transform.tif'],'PixelRegion',{ROI(1,1:2),ROI(2,1:2)}),[OutputFolder,'Channel4Image.tiff'],'WriteMode','append');
        pause(2);
    end
    end

end


num_cycles = 20;
num_channels = 4;


 %figure('Position', [10 10 2000 1000],'visible','off');
 figure('Position', [10 10 1000 500],'visible','off');

   p = tight_subplot(4,num_cycles/2,[0.001 0.001],[0.00001 0.00001],[0.001 0.001]);
   for jm = 1:num_cycles
       
       if BarcodeSequence(jm)==0
           continue
       end
    
       rgb_image = zeros(201,201,3);
       rgb_image2 = zeros(201,201,3);
       for channel=1:4
           temp1 = double(imread([BaseName,pad(num2str(jm),2,'left','0'),' channel ',int2str(channel),suffix,' transform.tif'],'PixelRegion',{[2900 3100],[2900 3100]}));
           temp1 = temp1./max(max(temp1));
           temp2 = double(imread([OutputFolder,'Channel' num2str(channel) 'Calls.tiff'],jm,'PixelRegion',{[2900 3100],[2900 3100]}));
           
           
           if channel == 1
               rgb_image(:,:,1) = temp1 +rgb_image(:,:,1);
               rgb_image2(:,:,1) = temp2 +rgb_image2(:,:,1);
           elseif channel == 2
               rgb_image(:,:,2) = temp1 +rgb_image(:,:,2);
               rgb_image(:,:,3) = temp1 +rgb_image(:,:,3);
               
               rgb_image2(:,:,2) = temp2 +rgb_image2(:,:,2);
               rgb_image2(:,:,3) = temp2 +rgb_image2(:,:,3);
           elseif channel == 3
               rgb_image(:,:,2) = temp1 +rgb_image(:,:,2);
               rgb_image2(:,:,2) = temp2 +rgb_image2(:,:,2);
           elseif channel == 4
               rgb_image(:,:,3) = temp1 +rgb_image(:,:,3);
               rgb_image2(:,:,3) = temp2 +rgb_image2(:,:,3);
           end
           
           
       end
       rgb_image(:,:,1) = imadjust(rgb_image(:,:,1)./(max(max(rgb_image(:,:,1)))));
       rgb_image(:,:,2) = imadjust(rgb_image(:,:,2)./(max(max(rgb_image(:,:,2)))));
       rgb_image(:,:,3) = imadjust(rgb_image(:,:,3)./(max(max(rgb_image(:,:,3)))));
       
       axes(p(floor((jm-1)/10)*num_cycles/2+jm)); imshow(rgb_image,[]);
       axes(p(floor((jm-1)/10)*num_cycles/2+jm + 10)); imshow(rgb_image2,[]);
   end
    saveas(gcf,[OutputFolder 'Basecalls.png'])
%% Some analysis of the certainty:
if 0
RandomIndices=ceil(10752*10752*rand(2000));
ReshapedCertaintyMap=reshape(CertaintyMap,ROIHeight*ROIWidth,l);
scatter(ReshapedCertaintyMap(RandomIndices,1),ReshapedCertaintyMap(RandomIndices,3));
end

%scatter(maxpixelvals(RandomIndices,1),maxpixelvals(RandomIndices,3));

if 1 %this is the part where we call barcodes. We need to tell it which ligations to use for barcode calling.

%To identify bead locations, we have to convert Indices into integer barcodes.
%We use base 6. I.e. the barcode '142342' gets converted to 2*6^0 + 4*6^1 +
%3*6^2 + etc. Note that 0 indicates that no base was read.

    
%% Calling barcodes from the bases called above

if DropBases
maxbarcodes=0;
maxindex=0;
for dropbase=0:14
    FlattenedBarcodes=uint64(zeros(ROIHeight,ROIWidth));
    NumSkippedBases=0;
    for mm=1:l
        if BarcodeSequence(mm)==0
            NumSkippedBases=NumSkippedBases+1;
            continue
        end
        m=BarcodeSequence(mm);
        if dropbase==m
            FlattenedBarcodes=FlattenedBarcodes+uint64(1)*5^(m-1);
        else
            FlattenedBarcodes=FlattenedBarcodes+uint64(Indices(:,:,mm))*5^(m-1);
        end
    end
    PresentBarcodes=unique(FlattenedBarcodes);
    %keyboard

    BarcodeOccCounts=histogram(FlattenedBarcodes,PresentBarcodes);
    manypixelbarcodeswithzeros=PresentBarcodes(BarcodeOccCounts.Values>BeadSizeThreshold);
    manypixelbarcodestmp=manypixelbarcodeswithzeros(cellfun(@numel,strfind(string(dec2base(manypixelbarcodeswithzeros,5,(l-NumSkippedBases))),'0'))<=BeadZeroThreshold);
    disp(['There are ',num2str(length(manypixelbarcodestmp)),' barcodes passing filter without base',num2str(dropbase),'.'])
    if length(manypixelbarcodestmp)>maxbarcodes
        if dropbase==0
            maxbarcodes=length(manypixelbarcodestmp)+15000; %We prefer to keep all the ligations
        else
            maxbarcodes=length(manypixelbarcodestmp);
        end
        maxindex=dropbase;
    end
end
else
    dropbase=0;
    maxindex=0;
end
    
FlattenedBarcodes=uint64(zeros(ROIHeight,ROIWidth));
NumSkippedBases=0;
for mm=1:l
    if BarcodeSequence(mm)==0
        NumSkippedBases=NumSkippedBases+1;
        continue
    end
    m=BarcodeSequence(mm);
        if maxindex==m
            FlattenedBarcodes=FlattenedBarcodes+uint64(1)*5^(m-1);
        else
            FlattenedBarcodes=FlattenedBarcodes+uint64(Indices(:,:,mm))*5^(m-1);
        end
end
PresentBarcodes=unique(FlattenedBarcodes);
%keyboard

BarcodeOccCounts=histogram(FlattenedBarcodes,PresentBarcodes);
manypixelbarcodeswithzeros=PresentBarcodes(BarcodeOccCounts.Values>BeadSizeThreshold);

figure(8)
histogram(BarcodeOccCounts.Values,0:2:500)
axis([0,500,0,1])
axis 'auto y'
set(gca,'yscale','log')
title('Pixels per Barcode')
%export_fig([OutputFolder,'Report_BaseCalling_',PuckName,'.pdf'],'-append');    %export_fig([OutputFolder,'Report.pdf'],'-append');
%print(figure(8),'-dpsc','-append',[OutputFolder,'Report_BaseCalling_',PuckName,'.ps']);
print(figure(8),'-dpng',[OutputFolder,'Report_BaseCalling_',PuckName,'_8','.png']);

%This is for the analysis of zeros:
BaseBalanceBarcodes=manypixelbarcodeswithzeros(cellfun(@numel,strfind(string(dec2base(manypixelbarcodeswithzeros,5,(l-NumSkippedBases))),'0'))<=7);
%The base 5 representations of the basecalls are:
BaseBalanceBase5Barcodes=cellfun(@(x) reverse(string(x)),{dec2base(BaseBalanceBarcodes,5,(l-NumSkippedBases))},'UniformOutput',false);
BaseBalanceBase5Barcodes=BaseBalanceBase5Barcodes{1};

BaseBalanceMatrix=zeros(5,l-NumSkippedBases);
for jp=1:(l-NumSkippedBases)
    testcmp0(jp)='0';
    testcmp1(jp)='1';
    testcmp2(jp)='2';
    testcmp3(jp)='3';
    testcmp4(jp)='4';
end
BaseBalanceMatrix(1,:)=sum(char(BaseBalanceBase5Barcodes)==testcmp0,1);
BaseBalanceMatrix(2,:)=sum(char(BaseBalanceBase5Barcodes)==testcmp1,1);
BaseBalanceMatrix(3,:)=sum(char(BaseBalanceBase5Barcodes)==testcmp2,1);
BaseBalanceMatrix(4,:)=sum(char(BaseBalanceBase5Barcodes)==testcmp3,1);
BaseBalanceMatrix(5,:)=sum(char(BaseBalanceBase5Barcodes)==testcmp4,1);
figure(77)
b=bar(BaseBalanceMatrix');
b(1).FaceColor='k';
b(2).FaceColor='b';
b(3).FaceColor='g';
b(4).FaceColor='y';
b(5).FaceColor='r';
title('For Barcodes with 7 nonzero entries, the base balance per ligation');
%export_fig([OutputFolder,'Report_BaseCalling_',PuckName,'.pdf'],'-append');
%export_fig([OutputFolder,'Report_BaseCalling.pdf'],'-append');
%print(figure(77),'-dpsc','-append',[OutputFolder,'Report_BaseCalling_',PuckName,'.ps']);
print(figure(77),'-dpng',[OutputFolder,'Report_BaseCalling_',PuckName,'_77','.png']);

NumZerosPlot=zeros(1,l-NumSkippedBases+1);
for kl=1:(l-NumSkippedBases+1)
    NumZerosPlot(kl)=size(manypixelbarcodeswithzeros(cellfun(@numel,strfind(string(dec2base(manypixelbarcodeswithzeros,5,(l-NumSkippedBases))),'0'))==kl-1),1);
end
    figure(76);
    bar(0:(l-NumSkippedBases),NumZerosPlot)
    title('Number of barcodes with a given number of 0s in them');
    %export_fig([OutputFolder,'Report_BaseCalling_',PuckName,'.pdf'],'-append');    %export_fig([OutputFolder,'Report.pdf'],'-append');
%print(figure(76),'-dpsc','-append',[OutputFolder,'Report_BaseCalling_',PuckName,'.ps']);
print(figure(76),'-dpng',[OutputFolder,'Report_BaseCalling_',PuckName,'_76','.png']);

%OLD CODE from the first analysis of Puck 8-5:
%nonzerobarcodes=PresentBarcodes(cellfun(@numel,strfind(string(dec2base(PresentBarcodes,5,(l-NumSkippedBases))),'0'))<=BeadZeroThreshold);
%beadhist=histogram(FlattenedBarcodes,nonzerobarcodes);% THIS DOESN'T WORK***
%manypixelbarcodestmp=nonzerobarcodes(beadhist.Values>BeadSizeThreshold);


%We make sure the length of manypixelbarcodes is divisible by NumPar to
%facilitate parallelization
manypixelbarcodestmp=manypixelbarcodeswithzeros(cellfun(@numel,strfind(string(dec2base(manypixelbarcodeswithzeros,5,(l-NumSkippedBases))),'0'))<=BeadZeroThreshold);
manypixelbarcodes=zeros(1,ceil(length(manypixelbarcodestmp)/NumPar)*NumPar);
manypixelbarcodes(1:length(manypixelbarcodestmp))=manypixelbarcodestmp; %We have to be careful here to get the indexing right.
%This is almost working but manypixelbarcodes still contains an element
%with 29 pixels rather than 30

disp(['There are ',num2str(length(manypixelbarcodestmp)),' barcodes passing filter.'])

%% Identifying which beads have significant clusters

%To parallelize, we break BeadImage up into a 3D array, with ParNum slices
%in the 3rd dimension. We reshape manypixelbarcodes so that it is a 2D
%array with ParNum slices in the 2nd dimension. And we likewise make
%BeadBarcodes and BeadLocations be 2d arrays. Then each worker gets its own
%row in BeadBarcodes, BeadLocations, and manypixelbarcodes, and runs the
%algorithm. At the end, we sum beadimage over the 3rd dimension and
%reshape BeadBarcodes and BeadLocations
BeadImage=false(ROIHeight,ROIWidth);
totalbarcodes=0;
delete(gcp('nocreate'));
pool=parpool(NumPar);

manypixelbarcodesforpar=reshape(manypixelbarcodes,ceil(length(manypixelbarcodes)/NumPar),NumPar);
BeadBarcodeCell={};
BeadLocationCell={};
BeadPixCell={};

parfor parnum=1:NumPar
    pp=0;
    LocalManyPixelBarcodes=manypixelbarcodesforpar(:,parnum);
    LocalBeadImage=false(ROIHeight,ROIWidth);
    LocalBeadBarcodes=zeros(1,nnz(manypixelbarcodes(:,parnum)));
    LocalBeadLocations=zeros(2,nnz(manypixelbarcodes(:,parnum)));
    LocalBeadPix=cell(1,nnz(manypixelbarcodes(:,parnum)));
    for qq=1:nnz(manypixelbarcodesforpar(:,parnum))
        %if qq/100==floor(qq/100)
            %disp(['Worker ',num2str(parnum),' is on barcode ',num2str(qq)])
        %end
        connected=bwconncomp(FlattenedBarcodes==LocalManyPixelBarcodes(qq));
        centroids=regionprops(connected,'Centroid');
    if max(cellfun(@numel,connected.PixelIdxList))>BeadSizeThreshold
        for t=1:length(connected.PixelIdxList)
            if numel(connected.PixelIdxList{t})>BeadSizeThreshold
                LocalBeadImage(connected.PixelIdxList{t})=true; 
                pp=pp+1;
                LocalBeadBarcodes(pp)=LocalManyPixelBarcodes(qq);
                LocalBeadLocations(:,pp)=centroids(t).Centroid;
                LocalBeadPix{pp}=connected.PixelIdxList{t};
            end
        end
    end
    end
    imwrite(LocalBeadImage,[OutputFolder,'Worker_',num2str(parnum),'_LocalBeadImage.tif']);
    BeadBarcodeCell{parnum}=LocalBeadBarcodes;
    BeadLocationCell{parnum}=LocalBeadLocations;
    BeadPixCell{parnum}=LocalBeadPix;
end

BeadBarcodeLength=0;
for k=1:NumPar
    BeadBarcodeLength=BeadBarcodeLength+length(BeadBarcodeCell{k});
end
BeadBarcodes=zeros(1,BeadBarcodeLength);
BeadLocations=zeros(2,BeadBarcodeLength);
BeadPixCelljoined=cell(1,BeadBarcodeLength);

delete(pool);

BeadBarcodeIndex=1;
for k=1:NumPar
    BeadBarcodes(BeadBarcodeIndex:(BeadBarcodeIndex+length(BeadBarcodeCell{k})-1))=BeadBarcodeCell{k};
    BeadLocations(:,BeadBarcodeIndex:(BeadBarcodeIndex+length(BeadBarcodeCell{k})-1))=BeadLocationCell{k};
    tmpcell=BeadPixCell{k};
    for ll=1:length(BeadBarcodeCell{k})
        BeadPixCelljoined{BeadBarcodeIndex+ll-1}=tmpcell{ll}; %if this is too long, we could also just make the beadpix cell array within the parfor above
    end
    BeadBarcodeIndex=BeadBarcodeIndex+length(BeadBarcodeCell{k});
    BeadImage=BeadImage + imread([OutputFolder,'Worker_',num2str(k),'_LocalBeadImage.tif']);
end
Bead=struct('Barcodes',num2cell(BeadBarcodes),'Locations',num2cell(BeadLocations,1),'Pixels',BeadPixCelljoined);

imwrite(BeadImage,[OutputFolder,'BeadImage.tif']);

% *_LocalBeadImage files are not useful any more
for k=1:NumPar
    BeadImageToDelete=[OutputFolder,'Worker_',num2str(k),'_LocalBeadImage.tif'];
    delete(BeadImageToDelete);
end


%% This is the non-parallel version
if 0
BeadImage=false(ROIHeight,ROIWidth);
BeadBarcodes=zeros(1,length(manypixelbarcodes));
BeadLocations=zeros(2,length(manypixelbarcodes));
pp=0;
totalbarcodes=0;

for qq=1:length(manypixelbarcodes)
    if qq/100==floor(qq/100)
        qq
    end
    connected=bwconncomp(FlattenedBarcodes==manypixelbarcodes(qq));
    centroids=regionprops(connected,'Centroid');
    if max(cellfun(@numel,connected.PixelIdxList))>BeadSizeThreshold
        for t=1:length(connected.PixelIdxList)
            if numel(connected.PixelIdxList{t})>BeadSizeThreshold
                BeadImage(connected.PixelIdxList{t})=true;
                pp=pp+1;
                BeadBarcodes(pp)=manypixelbarcodes(qq);
                BeadLocations(:,pp)=centroids(t).Centroid;
            end
        end
    end
end
%for q=1:length(BeadBarcodes)
%    if q/100==floor(q/100)
%        q
%    end
%    BeadImage=BeadImage | (FlattenedBarcodes==BeadBarcodes(q)); %this is not exactly correct.
%end
end
figure(78)
imshow(BeadImage)

save([OutputFolder,'AnalysisOutputs-selected'],'BeadImage','FlattenedBarcodes','Indices','Bead','BaseBalanceMatrix','NumZerosPlot','-v7.3')

%export_fig([OutputFolder,'\Report.pdf'],'-append');
fileid=fopen([OutputFolder,'Metrics.txt'],'w');
fprintf(fileid,['The total runtime for basecalling was ',num2str(toc(starttime)/60),' minutes.\n',...
    'There are ',num2str(length(manypixelbarcodestmp)),' barcodes passing filter.\n',...
    'BeadSizeThreshold=',num2str(BeadSizeThreshold),'.\n',...
    'PixelThreshold=',num2str(PixelThreshold),'.\n',...
    'Cy3TxRMixing=',num2str(Cy3TxRMixing),'.\n',...
    'PreviousRoundMixing=',num2str(PreviousRoundMixing),'.\n',...
    'EnforceBaseBalance=',num2str(EnforceBaseBalance),'.\n',...
    'BaseBalanceTolerance=',num2str(BaseBalanceTolerance),'.\n',...
    'BeadZeroThreshold=',num2str(BeadZeroThreshold)...
    ]);
fclose(fileid);




end