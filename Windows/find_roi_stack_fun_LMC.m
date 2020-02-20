function find_roi_stack_fun_LMC(BaseName,suffix,ImageSize,varargin)
% 

delete(gcp('nocreate'));
clearvars -except f1s d1s database2 BaseName suffix ImageSize varargin;

%run('D:\Dropbox\Insitubiology Dropbox\insitubiology\Project - SlideSeq\BeadSeq Code\find_roi\helpers\vlfeat-0.9.20\toolbox\vl_setup.m');
%addpath('D:\Dropbox\Insitubiology Dropbox\insitubiology\Project - SlideSeq\BeadSeq Code\find_roi\helpers\');

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

% PixelCutoff=300;
% index = find(cellfun(@(x) (all(ischar(x)) || isstring(x))&&(string(x)=="PixelCutoff"), varargin, 'UniformOutput', 1));
% if ~isempty(index)
%     PixelCutoff=varargin{index+1};
% end

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

% l=0;
% while true
%     if exist([BaseName,pad(num2str(l+1),2,'left','0'),suffix,'.tif'],'file')
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

%pool=parpool(NumPar);
%addAttachedFiles(pool,'D:\Dropbox\Insitubiology Dropbox\insitubiology\Project - SlideSeq\BeadSeq Code\find_roi\helpers\fit_isometry.m');

%for mm=2:l
    %queryOrig=max(queryOrigstack(:,:,:,mm),[],3);
    query=max(querystack(:,:,:),[],3);
    query1=imresize(query, scaleFactorDown);
    
    tformEstimate = imregcorr(query1,map1);
    tformEstimate.T(3,1)=tformEstimate.T(3,1)/scaleFactorDown;
    tformEstimate.T(3,2)=tformEstimate.T(3,2)/scaleFactorDown;
    Rfixed = imref2d(size(map));
    %movingReg = imwarp(query,tformEstimate,'OutputView',Rfixed);
    %figure()
    %imshowpair(map,movingReg)
    
%     %When isPrecomputed is not in use, db_old is not used either
%     if 0
%         if exist('database2','var')
%             db_old = database2; %Store copy of existing map tiles
%         else
%             db_old = {};
%         end
%     end    
%     % Generate database of tiles
%     [m,n] = size(map);
%     N = ceil(n/tileSize);
%     M = ceil(m/tileSize);
%     nTiles = M*N;
%     database2 = cell(1,nTiles);
%     for i = 1:M
%         for j = 1:N
%             img = im2single(map((i-1)*floor(m/M)+1:i*min(floor(m/M),m),...
%                 (j-1)*floor(n/N)+1:j*min(floor(n/N),n)));
%             database2{(i-1)*N+j} = img/max(img(:)); %Normalize intensity
%         end
%     end
% 
%     % Check if SIFT keypoints already exist in workspace
%     if 0 %The SIFT keypoints are never precomputed in the parfor
%     isPrecomputed = exist('f1s','var') && exist('d1s','var') ...
%         && exist('database2','var') && iscell(f1s) && iscell(d1s) ...
%         && iscell(database2) && (numel(f1s) == numel(database2)) && ...
%         (numel(d1s) == numel(database2)) && isequal(database2,db_old);
    
        for k=1:4
            final= imwarp(squeeze(queryOrigstack(:,:,k)),tformEstimate,'OutputView',Rfixed);
            final=final(1:ImageSize,1:ImageSize);
            imwrite(final,[BaseName,pad(num2str(mm),2,'left','0'),' channel ',int2str(k),suffix,' transform.tif'])
        end
        
%       k=1
%        imwrite(imtransform(queryOrigstack1(:,:,mm),tform,'XData',[1, size(query,2)],'YData',[1, size(query,1)]),[BaseName,pad(num2str(mm),2,'left','0'),' channel ',int2str(k),suffix,' transform.tif'])
%        k=2;
%        imwrite(imtransform(queryOrigstack2(:,:,mm),tform,'XData',[1, size(query,2)],'YData',[1, size(query,1)]),[BaseName,pad(num2str(mm),2,'left','0'),' channel ',int2str(k),suffix,' transform.tif'])
%        k=3;
%        imwrite(imtransform(queryOrigstack3(:,:,mm),tform,'XData',[1, size(query,2)],'YData',[1, size(query,1)]),[BaseName,pad(num2str(mm),2,'left','0'),' channel ',int2str(k),suffix,' transform.tif'])
%        k=4;
%        imwrite(imtransform(queryOrigstack4(:,:,mm),tform,'XData',[1, size(query,2)],'YData',[1, size(query,1)]),[BaseName,pad(num2str(mm),2,'left','0'),' channel ',int2str(k),suffix,' transform.tif'])
%     catch ME
%         disp(['The following error was caught while writing out the transformed images for mm=',num2str(mm),' and BaseName=',BaseName,':'])
%         disp([ME.identifier,': ',ME.message])
%         disp('The transform is:')
%         %disp(tform.tdata)
    
%delete(pool);
end
