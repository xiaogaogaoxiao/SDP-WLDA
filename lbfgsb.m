function [x,f,info] = lbfgsb( fcn, l, u, opts )
% x = lbfgsb( fcn, l, u )
%   uses the lbfgsb v.3.0 library (fortran files must be installed;
%       see compile_mex.m ) which is the L-BFGS-B algorithm.
%   The algorithm is similar to the L-BFGS quasi-Newton algorithm,
%   but also handles bound constraints via an active-set type iteration.
%
%  The minimization problem that is solves is:
%       min_x  f(x)     subject to   l <= x <= u
%
% 'fcn' is a function handle that accepts an input, 'x',
%   and returns two outputs, 'f' (function value), and 'g' (function gradient).
%
% 'l' and 'u' are column-vectors of constraints. Set their values to Inf
%   if you want to ignore them. (You can set some values to Inf, but keep
%   others enforced).
%
% The full format of the function is:
% [x,f,info] = lbfgsb( fcn, l, u, opts )
%   where the output 'f' has the value of the function f at the final iterate
%   and 'info' is a structure with useful information
%       (self-explanatory, except for info.err. The first column of info.err
%        is the history of the function values f, and the second column
%        is the history of norm( gradient, Inf ).  )
%
%   The 'opts' structure allows you to pass further options.
%   Possible field name values:
%
%       opts.x0     The starting value (default: all zeros)
%       opts.m      Number of limited-memory vectors to use in the algorithm
%                       Try 3 <= m <= 20. (default: 5 )
%       opts.factr  Tolerance setting (see this source code for more info)
%                       (default: 1e7 ). This is later multiplied by machine epsilon
%       opts.pgtol  Another tolerance setting, relating to norm(gradient,Inf)
%                       (default: 1e-5)
%       opts.maxits         How many iterations to allow (default: 100)
%       opts.maxTotalIts    How many iterations to allow, including linesearch iterations
%                       (default: 5000)
%       opts.printEvery     How often to display information (default: 1)
%       opts.errFcn         A function handle (or cell array of several function handles)
%                       that computes whatever you want. The output will be printed
%                       to the screen every 'printEvery' iterations. (default: [] )
%       opts.outputFcn      Similar to 'errFcn', but will save the output to
%                       the info.err variable.
%
% Stephen Becker, srbecker@alumni.caltech.edu
% Feb 14, 2012


global flag;
error(nargchk(3, 4, nargin, 'struct'))
if nargin < 4, opts = struct([]); end

% Matlab doesn't let you use the .name convention with structures
%   if they are empty, so in that case, make the structure non-empty:
if isempty(opts), opts=struct('a',1) ; end

function out = setOpts( field, default, mn, mx )
    if ~isfield( opts, field )
        opts.(field)    = default;
    end
    out = opts.(field);
    if nargin >= 3 && ~isempty(mn) && any(out < mn), error('Value is too small'); end
    if nargin >= 4 && ~isempty(mx) && any(out > mx), error('Value is too large'); end
    opts    = rmfield( opts, field ); % so we can do a check later
end

% [f,g] = callF( x );
if iscell(fcn)
    % the user has given us separate functions to compute
    %   f (function) and g (gradient)
    callF   = @(x) fminunc_wrapper(x,fcn{1},fcn{2} );
else
    callF   = fcn;
end


n   = length(l); 
if length(u) ~= length(l), error('l and u must be same length'); end
x0  = setOpts( 'x0', zeros(n,1) );
x   = x0 + 0; % important: we want Matlab to make a copy of this. 
              %  'x' will be modified in-place
              
if size(x0,2) ~= 1, error('x0 must be a column vector'); end
if size(l,2) ~= 1, error('l must be a column vector'); end
if size(u,2) ~= 1, error('u must be a column vector'); end
if size(x,1) ~= n, error('x0 and l have mismatchig sizes'); end
if size(u,1) ~= n, error('u and l have mismatchig sizes'); end

% Number of L-BFGS memory vectors
% From the fortran driver file:
% "Values of m < 3  are not recommended, and 
%  large values of m can result in excessive computing time. 
%  The range  3 <= m <= 20 is recommended.  "
m   = setOpts( 'm', 5, 0 );


% 'nbd' is 0 if no bounds, 1 if lower bound only,
%       2 if both upper and lower bounds, and 3 if upper bound only.
% This .m file assumes l=-Inf and u=+Inf imply that there are no constraints.
% So, convert this to the fortran convention:
nbd     = isfinite(l) + isfinite(u) + 2*isinf(l).*isfinite(u);


% Some scalar settings, "factr" and "pgtol"
% Their descriptions, from the fortran file:

%     factr is a DOUBLE PRECISION variable that must be set by the user.
%       It is a tolerance in the termination test for the algorithm.
%       The iteration will stop when
%
%        (f^k - f^{k+1})/max{|f^k|,|f^{k+1}|,1} <= factr*epsmch
%
%       where epsmch is the machine precision which is automatically
%       generated by the code. Typical values for factr on a computer
%       with 15 digits of accuracy in double precision are:
%       factr=1.d+12 for low accuracy;
%             1.d+7  for moderate accuracy; 
%             1.d+1  for extremely high accuracy.
%       The user can suppress this termination test by setting factr=0.
factr   = setOpts( 'factr', 1e7 );

%     pgtol is a double precision variable.
%       On entry pgtol >= 0 is specified by the user.  The iteration
%         will stop when
%
%                 max{|proj g_i | i = 1, ..., n} <= pgtol
%
%         where pg_i is the ith component of the projected gradient.
%       The user can suppress this termination test by setting pgtol=0.
pgtol   = setOpts( 'pgtol', 1e-5 );


% Maximum number of outer iterations
maxIts  = setOpts( 'maxIts', 100, 1 );

% Maximum number of total iterations
%   (this includes the line search steps )
maxTotalIts     = setOpts( 'maxTotalIts', 5e3 );

% Print out information this often:
printEvery  = setOpts( 'printEvery', 500 );

errFcn      = setOpts( 'errFcn', [] );
outputFcn   = setOpts( 'outputFcn', [] );
width       = 0;
if iscell( outputFcn ), width = length(outputFcn); 
elseif ~isempty(outputFcn), width = 1; end
width       = width + 2; % include fcn and norm(grad) as well
err         = zeros( maxIts, width );

% Make the work arrays
wa      = ones(2*m*n + 5*n + 11*m*m + 8*m,1);
iwa     = ones(3*n,1,'int32');
task    = 'START';
iprint  = 0;
csave   = '';
lsave   = zeros(4,1);
isave   = zeros(44,1, 'int32');
dsave   = zeros(29,1);
f       = 0;
g       = zeros(n,1);


outer_count     = 0;
for k = 1:maxTotalIts
    
    % Call the mex file. The way it works is that you call it,
    %   then it returns a "task". If that task starts with 'FG',
    %   it means it is requesting you to compute the function and gradient,
    %   and then call the function again.
    % If it is 'NEW_X', it means it has completed one full iteration.
    [f, task, csave, lsave, isave, dsave] = ...
        lbfgsb_wrapper( m, x, l, u, nbd, f, g, factr, pgtol, wa, iwa, task,iprint,...
        csave, lsave, isave, dsave );
    
    task    = deblank(task(1:60)); % this is critical! 
                                   %otherwise, fortran interprets the string incorrectly
    
    if 1 == strfind( task, 'FG' )
        % L-BFGS-B requests that we compute the gradient and function value
        
        [f,g] = callF( x );

         if flag ==1
             flag
            disp('Infeasible, exiting...');
            break;
         end
        
    elseif 1 == strfind( task, 'NEW_X' )
        outer_count     = outer_count + 1;
        
        % Display information if requested
        if ~mod( outer_count, printEvery )
            fprintf('Iteration %4d, f = %5.2e, ||g||_inf = %5.2e', ...
                outer_count, f, norm(g,Inf) );
            if isa( errFcn, 'function_handle' )
                fprintf('; error %.2e', errFcn(x) );
            elseif iscell( errFcn )
                for j = 1:length(errFcn)
                    fprintf('; err %.2e', errFcn{j}(x) );
                end
            end
            fprintf('\n');
        end
        
        err(outer_count,1)  = f;
        err(outer_count,2)  = norm(g,Inf);
        
        
        % Record information for the output, if requested
        % e.g. outputFcn = errFcn
        if isa( outputFcn, 'function_handle' )
            err(outer_count,3) = outputFcn(x);
        elseif iscell( outputFcn )
            for j = 1:length(outputFcn)
                err(outer_count,k+2) = outputFcn{j}(x);
            end
        end
        
         if flag ==1
             flag
            disp('Infeasible, exiting...');
            break;
         end
        
        if outer_count >= maxIts
            disp('Maxed-out iteration counter, exiting...');
            break;
        end
        
        
        
    else
        break;
    end
end
if k == maxTotalIts, disp('Maxed-out the total iteration counter, exiting...'); end
info.err    = err(1:outer_count,:);
info.iterations     = outer_count;
info.totalIterations = k;
info.lbfgs_message1  = task;
info.lbfgs_message2  = csave;
info.g  = g;

end % end of main function


function [f,g] = fminunc_wrapper(x,F,G)
% [f,g] = fminunc_wrapper( x, F, G )
%   for use with Matlab's "fminunc"
f = F(x);
if nargin > 2 && nargout > 1
    g = G(x);
end

end