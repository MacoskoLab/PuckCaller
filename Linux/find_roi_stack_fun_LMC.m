function find_roi_stack_fun_LMC(BaseName,suffix,ImageSize,varargin)

delete(gcp('nocreate'));
clearvars -except f1s d1s database2 BaseName suffix ImageSize varargin;

displayfigs=0;

RegisterColorChannels=1;
index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="RegisterColorChannels"), varargin, 'UniformOutput', 1));
if ~isempty(index)
    RegisterColorChannels=varargin{index+1};
end

XCorrBounds=[1,ImageSize,1,ImageSize];
index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="XCorrBounds"), varargin, 'UniformOutput', 1));
if ~isempty(index)
    XCorrBounds=varargin{index+1};
end

channelnum=4; %number of channels
index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="NumChannels"), varargin, 'UniformOutput', 1));
if ~isempty(index)
    channelnum=varargin{index+1};
end

NumPar=10; 
index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="NumPar"), varargin, 'UniformOutput', 1));
if ~isempty(index)
    NumPar=varargin{index+1};
end

BarcodeSequence=[1,2,3,4,0,5,0,6,0,7,8,9,10,11,0,12,0,13,0,14];
index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="BarcodeSequence"), varargin, 'UniformOutput', 1));
if ~isempty(index)
    BarcodeSequence=varargin{index+1};
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Adjustable parameters
% tileSize = 10500; %Decrease if out of memory. Default was 3500. One problem we're having possibly is that when the images are translate too far down in Y, then there aren't enough keypoints in the upper left quadrant to make the match.
% peakThresh = 0; %SIFT peak threshold
% edgeThresh = 10; %SIFT edge threshold. default 10
% nRansacTrials = 1000000; %2000 by default. Increase for more reliable matching
% nPtsFit = 2; %For each RANSAC trial
% nKeypointsThresh = 30; %Minimum number of keypoint matches. Default was 50. We use a very low threshold because the match is essentially always on tile 1.
% radius = 5; %Maximum tolerated RANSAC distance. 20 by default.
% MatchThresh=1.5; %default is 1.5. Two keypoints d1 and d2 are matched only if the distance between them times this number is not greater than the distance between d1 and all other keypoints.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%NOTE: For a typical nimage on which the algorithm works, it will find 12000
%features in one tile of the master image of size 3500; and it will find 400000 features in the
%whole query image.

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

for k=1:channelnum
    mapOrigstack(:,:,k)=imread([BaseName,pad(num2str(starti),2,'left','0'),suffix,'.tif'],'index',k); %,'PixelRegion',{[1,ImageSize],[1,ImageSize]}
end

if RegisterColorChannels
    mapOrigstack=uint16(FindTranslationXCorr_LMC(mapOrigstack,'XCorrBounds',XCorrBounds));
end

for k=1:channelnum
    mapstack(:,:,k) = im2single(imadjust(mapOrigstack(:,:,k)));
end

scaleFactorDown = 1/4;
map=max(mapstack,[],3);
map1=imresize(map, scaleFactorDown);

for k=1:channelnum
    mapCrop = mapOrigstack(:,:,k);
    mapCrop = mapCrop(1:ImageSize,1:ImageSize);
    imwrite(mapCrop,[BaseName,pad(num2str(starti),2,'left','0'),' channel ',num2str(k),suffix,' transform.tif'])
end

for mm=(starti+1):l
    if BarcodeSequence(mm)==0
        continue
    end
    display(strcat('Loading file for ligation ',num2str(mm)))
    for k=1:channelnum
        queryOrigstack(:,:,k)=imread([BaseName,pad(num2str(mm),2,'left','0'),suffix,'.tif'],'index',k);%,'PixelRegion',{[1,ImageSize],[1,ImageSize]}
    end

    if RegisterColorChannels
        display(['Registering color channels for ligation ',num2str(mm)])
        queryOrigstack(:,:,:)=uint16(FindTranslationXCorr_LMC(squeeze(queryOrigstack(:,:,:)),'XCorrBounds',XCorrBounds));
    end

    for k=1:channelnum
        querystack(:,:,k) = im2single(imadjust(queryOrigstack(:,:,k)));
    end

    query=max(querystack(:,:,:),[],3);
    query1=imresize(query, scaleFactorDown);
    
    tformEstimate = imregcorr(query1,map1);
    tformEstimate.T(3,1)=tformEstimate.T(3,1)/scaleFactorDown;
    tformEstimate.T(3,2)=tformEstimate.T(3,2)/scaleFactorDown;
    Rfixed = imref2d(size(map));   
    
	for k=1:4
		final= imwarp(squeeze(queryOrigstack(:,:,k)),tformEstimate,'OutputView',Rfixed);
		final=final(1:ImageSize,1:ImageSize);
		imwrite(final,[BaseName,pad(num2str(mm),2,'left','0'),' channel ',int2str(k),suffix,' transform.tif'])
	end
end
