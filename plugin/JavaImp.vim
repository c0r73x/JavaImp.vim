" -------------------------------------------------------------------
" Mappings
" -------------------------------------------------------------------

command! -nargs=? JIX              call s:JavaImpQuickFix()
command! -nargs=? JI               call s:JavaImpInsert()
command! -nargs=? JavaImp          call s:JavaImpInsert()

command! -nargs=? JIG              call s:JavaImpGenerate()
command! -nargs=? JavaImpGenerate  call s:JavaImpGenerate()

command! -nargs=? JIS              call s:JavaImpSort()
command! -nargs=? JavaImpSort      call s:JavaImpSort()

command! -nargs=? JID              call s:JavaImpDoc()
command! -nargs=? JavaImpDoc       call s:JavaImpDoc()

command! -nargs=? JIF              call s:JavaImpFile()
command! -nargs=? JavaImpFile      call s:JavaImpFile()

command! -nargs=? JIFS             call s:JavaImpFile()
command! -nargs=? JavaImpFileSplit call s:JavaImpFile()

" -------------------------------------------------------------------
" Default configuration
" -------------------------------------------------------------------

if(has('unix'))
    let s:SL = '/'
elseif(has('win16') || has('win32') || has('win95') ||
            \has('dos16') || has('dos32') || has('os2'))
    let s:SL = '\\'
else
    let s:SL = '/'
endif

if !exists('g:JavaImpDataDir')
    let g:JavaImpDataDir = expand('$HOME') . s:SL . 'vim' . s:SL . 'JavaImp'
endif

if !exists('g:JavaImpClassList')
    let g:JavaImpClassList = g:JavaImpDataDir . s:SL . 'JavaImp.txt'
endif

" Order import statements which match these regular expressions in the order
" of the expression.  The default setting sorts import statements with java.*
" first, then javax.*, then org.*, then com.*, and finally everything else
" alphabetically after that.  These settings emulate Eclipse's settings.
if !exists('g:JavaImpTopImports')
    let g:JavaImpTopImports = [
        \ 'java\..*',
        \ 'javax\..*',
        \ 'org\..*',
        \ 'com\..*'
        \ ]
endif

" Put the Static Imports First if 1, otherwise put the Static Imports last.
" Defaults to 1.
if !exists('g:JavaImpStaticImportsFirst')
    let g:JavaImpStaticImportsFirst = 1
endif

if !exists('g:JavaImpVerbose')
    let g:JavaImpVerbose = 0
endif

" Deprecated
if !exists('g:JavaImpJarCache')
    let g:JavaImpJarCache = g:JavaImpDataDir . s:SL . 'cache'
endif

if !exists('g:JavaImpSortRemoveEmpty')
    let g:JavaImpSortRemoveEmpty = 1
endif

" Note if the SortPkgSep is set, then you need to remove the empty lines.
if !exists('g:JavaImpSortPkgSep')
    if (g:JavaImpSortRemoveEmpty == 1)
        let g:JavaImpSortPkgSep = 2
    else
        let g:JavaImpSortPkgSep = 0
    endif
endif

if !exists('g:JavaImpPathSep')
    let g:JavaImpPathSep = ','
endif

if !exists('g:JavaImpDocViewer')
    let g:JavaImpDocViewer = 'w3m'
endif

" -------------------------------------------------------------------
" Generating the imports table
" -------------------------------------------------------------------

"Generates the mapping file
function! s:JavaImpGenerate()
    if (s:JavaImpChkEnv() != 0)
        return
    endif
    " We would like to save the current buffer first:
    if expand('%') !=# ''
        update
    endif
    cclose
    "Recursivly go through the directory and write to the temporary file.
    let l:sourceList = []
    let currPaths = g:JavaImpPaths
    " See if currPaths has a separator at the end, if not, we add it.
        "echo 'currPaths begin is ' . currPaths
    if (match(currPaths, g:JavaImpPathSep . '$') == -1)
        let currPaths = currPaths . g:JavaImpPathSep
    endif

    while (currPaths !=# '' && currPaths !~ '^ *' . g:JavaImpPathSep . '$')
        " Cut off the first path from the delimeted list of paths to examine.
        let sepIdx = stridx(currPaths, g:JavaImpPathSep)
        let currPath = strpart(currPaths, 0, sepIdx)

        " Uncertain what this is doing.
        " currPath is the same before and after.
        let pkgDepth = substitute(currPath, '^.*{\(\d\+\)}.*$', '\1', '')
        let currPath = substitute(currPath, '^\(.*\){.*}.*', '\1', '')

        let headStr = ''
        while (pkgDepth != 0)
            let headStr = headStr . ':h'
            let pkgDepth = pkgDepth - 1
        endwhile

        let pathPrefix = fnamemodify(currPath, headStr)
        let currPkg = strpart(currPath, strlen(pathPrefix) + 1)

        echo 'Searching in path (package): ' . currPath . ' (' . currPkg .  ')'
        "echo 'currPaths: '.currPaths
        let currPaths = strpart(currPaths, sepIdx + 1, strlen(currPaths) - sepIdx - 1)
        "echo '('.currPaths.')'
        let l:sourceList = l:sourceList + s:JavaImpAppendClass(currPath, currPkg)
    endwhile

    "silent exe 'write! /tmp/raw'
    let classCount = len(l:sourceList)

    " Formatting the file
    "echo 'Formatting the file...'
    let l:sourceList = s:JavaImpFormatList(l:sourceList)
    "silent exe 'write! /tmp/raw_formatted'

    "echo 'Assuring uniqueness...'
    let uniqueClassCount = len(l:sourceList)
    "silent exe 'write! /tmp/raw_unique'

    call writefile(l:sourceList, g:JavaImpClassList)
    echo 'Done.  Found ' . classCount . ' classes ('. uniqueClassCount. ' unique)'
endfunction

" The helper function to append a class entry in the class list
function! s:JavaImpAppendClass(cpath, relativeTo)
    let l:sourceList = []

    " echo 'Arguments ' . a:cpath . ' package is ' . a:relativeTo
    if strlen(a:cpath) < 1
        echo 'Alert! Bug in JavaApppendClass (JavaImp.vim)'
        echo ' - null cpath relativeTo '.a:relativeTo
        echo '(beats me... hack the source and figure it out)'
        " Base case... infinite loop protection
        return 0
    elseif (!isdirectory(a:cpath) && match(a:cpath, '\(\.class$\|\.java$\)') > -1)
        " oh good, we see a single entry like org/apache/xerces/bubba.java
        " just slap it on our tmp buffer
        if (a:relativeTo ==# '')
            call add(l:sourceList, a:cpath)
        else
            call add(l:sourceList, a:relativeTo)
        endif
    elseif (isdirectory(a:cpath))
        " Recursively fetch all Java files from the provided directory path.
        let l:javaList = glob(a:cpath . '/**/*.java', 1, 1)
        let l:clssList = glob(a:cpath . '/**/*.class', 1, 1)
        let l:list = l:javaList + l:clssList

        " Include a trailing slash so that we don't leave a slash at the
        " beginning of the fully qualified classname.
        let l:cpath = a:cpath . '/'

        " Add each matching file to the class index buffer.
        " The format of each entry will be akin to: org/apache/xerces/Bubba
        for l:filename in l:list
            let l:filename = substitute(l:filename, l:cpath, '', 'g')
            call add(l:sourceList, l:filename)
        endfor

    elseif (match(a:cpath, '\(\.jar$\)') > -1)
        " Check if the jar file exists, if not, we return immediately.
        if (!filereadable(a:cpath))
            echo 'Skipping ' . a:cpath . '. File does not exist.'
            return 0
        endif
        " If we get a jar file, we first tries to match the timestamp of the
        " cache defined in g:JavaImpJarCache directory.  If the jar is newer,
        " then we would execute the jar command.  Otherwise, we just slap the
        " cached file to the buffer.
        "
        " The cached entries are organized in terms of the relativeTo path
        " with the '/' characters replaced with '_'.  For example, if you have
        " your jar in the directory /blah/lib/foo.jar, you'll have a cached
        " file called _blah_lib_foo.jmplst in your cache directory.

        let l:jarcache = expand(g:JavaImpJarCache)
        let l:jarcmd = 'jar -tf "'.a:cpath . '"'
        let l:sourceList = l:sourceList + split(system(l:jarcmd))
    elseif (match(a:cpath, '\(\.jmplst$\)') > -1)
        " a jmplist is something i made up... it's basically the output of a jar -tf
        " operation.  Why is this useful?
        " 1) to save time if there is a jar you read frequently (jar -tf is slow)
        " 2) because the java src.jar (for stuff like javax.swing)
        "    has everything prepended with a "src/", for example "src/javax/swing", so
        "    what i did was to run that through perl, stripping out the src/ and store
        "    the results in as java-1_3_1.jmplist in my .vim directory...

        " we just insert its contents into the buffer
        "echo '  - jmplst: ' . fnamemodify(a:cpath, ':t') . "\n"
        let l:sourceList = l:sourceList + split(system('cat ' . a:cpath))
    endif

    return l:sourceList
endfunction

" Converts the current line in the buffer from a java|class file pathname
"  into a space delimited class package
" For example:
"  /javax/swing/JPanel.java
"  becomes:
"  JPanel javax.swing
" If the current line does not appear to contain a java|class file,
" we blank it out (this is useful for non-bytecode entries in the
" jar files, like gif files or META-INF)
function! s:JavaImpFormatList(sourceList)
let l:sourceList = []
python << endpython
import vim
import ntpath
import re

lines = vim.eval("a:sourceList")

for i in range(len(lines)):
    subdir = ntpath.dirname(lines[i]);
    pkg = subdir.replace("/", ".");

    match = re.search(r'[\\/]([\$0-9A-Za-z_]*)\.(class|java)$', lines[i]);
    if match:
        name = match.group(1)
        name = name.replace("$", ".");
        lines[i] = "%s %s.%s" % (name, pkg, name)
    else:
        lines[i] = ""

lines = filter(None, lines)
vim.command("let l:sourceList = %s"% list(set(lines)))
endpython
return l:sourceList
endfunction

" -------------------------------------------------------------------
" Inserting imports
" -------------------------------------------------------------------

" Inserts the import statement of the class specified under the cursor in the
" current .java file.
"
" If there is a duplicated entry for the classname, it'll insert the entry as
" comments (starting with "//")
"
" If the entry already exists (specified in an import statement in the current
" file), this will do nothing.
"
" pass 0 for verboseMode if you want fewer updates of what this function is
"  doing, or 1 for normal verbosity
" (silence is interesting if you're scripting the use of JavaImpInsert...
"  for example, i have a script that runs JavaImpInsert on all the
"  class not found errors)
function! s:JavaImpInsert()
    if (s:JavaImpChkEnv() != 0)
        return
    endif
    if g:JavaImpVerbose
        let verbosity = '' 
    else
        let verbosity = 'silent'
    end

    " Write the current buffer first (if we have to).  Note that we only want
    " to do this if the current buffer is named.
    if expand('%') !=# ''
        exec verbosity 'update'
    endif

    " choose the current word for the class
    let className = expand('<cword>')
    let fullClassName = s:JavaImpCurrFullName(className)

    if (fullClassName !=# '')
        if verbosity !=# 'silent'
            echo 'Import for ' . className . ' found in this file.'
        endif
    else
        let fullClassName = s:JavaImpFindFullName(className)
        if (fullClassName ==# '')
            if ! g:JavaImpVerbose
                echo className.' not found (you should update the class map file)'
            else
                echo 'Can not find any class that matches ' . className . '.'
                let input = confirm('Do you want to update the class map file?', "&Yes\n&No", 2)
                if (input == 1)
                    call s:JavaImpGenerate()
                    return
                endif
            endif
        else
            let importLine = 'import ' . fullClassName . ';'
            let importLoc = s:JavaImpGotoLast()

            let pkgLoc = s:JavaImpGotoPackage()
            if (pkgLoc > -1)
                let pkgPat = '^\s*package\s\+\(\%(\w\+\.\)*\w\+\)\s*;.*$'
                let pkg = substitute(getline(pkgLoc), pkgPat, '\1', '')

                " Check to see if the class is in this package, we won't
                " need an import.

                if (fullClassName == (pkg . '.' . className))
                    let importLoc = -2
                else
                    if (importLoc == -1)
                        let pkgLoc += 1
                        let importLoc = pkgLoc + 1
                    endif
                endif
            endif

            let importLoc = (importLoc < 0) ? 0 : importLoc
            exec verbosity 'call append(importLoc, importLine)'

            if g:JavaImpVerbose
                if (importLoc >= 0)
                    echo 'Inserted ' . fullClassName . ' for ' . className
                else
                    echo 'Import unneeded (same package): ' . fullClassName
                endif
            endif

            " go back to the old location
            call s:JavaImpSort()
        endif
    endif
endfunction

" Given a classname, try to search the current file for the import statement.
" If found, it'll return the fully qualify classname.  Otherwise, it'll return
" an empty string.
function! s:JavaImpCurrFullName(className)
python << endpython
import vim
import re

lines = vim.current.buffer
className = vim.eval('a:className')
for line in lines:
    imp = re.match(r"^\s*import\s\s*(.*\." + className + ')\s*;',line)
    if imp:
        vim.command('return "%s"'% imp.group(1))
        break;
endpython
    return ''
endfunction

" Given a classname, try to search the current file for the import statement.
" If found, it'll return the fully qualify classname.  If not found, it'll try
" to search the import list for the match.
function! s:JavaImpFindFullName(className)
    " notice that we switch to the JavaImpClassList buffer
    " (or load the file if needed)
    let icl = expand(g:JavaImpClassList)
    if !(filereadable(icl))
        echo 'Can not load the class map file ' . icl . '.'
        return ''
    endif
    let importLine = ''
    let importCtr = 0
    let firstImport = 0
    let firstFullPackage = ''

python << endpython
import vim
import re

icl = vim.eval('icl')
className = vim.eval('a:className')
lines = [line.strip() for line in open(icl, 'r')]
pkglist = []
idx = [i for i, line in enumerate(lines) if re.search('^%s '% className, line)]

vim.command('let importCtr = %d'% len(idx))
if (len(idx) > 0):
    for i in range(len(idx)):
        pkg = re.search(r"\S* (.*)$", lines[idx[i]]).group(1)
        pkglist.append(pkg)

    vim.command('let importLine = "%s"'% '\n'.join(pkglist))
endpython

    if (importCtr ==# 0)
        return ''
    else
        let pickedImport = s:JavaImpChooseImport(
                    \ importCtr, a:className, importLine)

        return pickedImport
    endif
endfunction

" -------------------------------------------------------------------
" Choosing and caching imports
" -------------------------------------------------------------------

" Check with the choice cache and determine the final order of the import
" list.
" The choice cache is a file with the following format:
" [className1] [most recently used class] [2nd most recently used class] ...
" [className2] [most recently used class] [2nd most recently used class] ...
" ...
"
" imports and the return list consists of fully-qualified classes separated by
" \n.  This function will list the imports list in the order specified by the
" choice cache file
"
" IMPORTANT: if the choice is not available in the cache, this returns
" empty string, not the imports
function! s:JavaImpMakeChoice(imctr, className, imports)
    let jicc = expand(g:JavaImpDataDir) . s:SL . 'choices.txt'
    if !filereadable(jicc)
        return ''
    endif

python << endpython
import vim
import re

jicc = vim.eval('jicc')
className = vim.eval('a:className')

lines = [line.strip() for line in open(jicc, 'r')]
idx = [i for i, line in enumerate(lines) if re.search('^%s '% className, line)]

if (len(idx) > 0):
    pkg = re.search(r"\S* (.*)$", lines[idx[0]]).group(1)
    vim.command('return s:JavaImpOrderChoice(a:imctr, "%s", a:imports)'% pkg)
else:
    vim.command("return ''")
endpython
endfunction

" Order the imports with the cacheLine and returns the list.
function! s:JavaImpOrderChoice(imctr, cacheLine, imports)
    " we construct the imports so we can test for <space>classname<space>
    let il = ' ' . substitute(a:imports, "\n", ' ', 'g') . ' '
    "echo 'orig: ' . a:imports
    "echo 'il: ' . il
    let rtn = ' '
    " We first construct check each entry in the cacheLine to see if it's in
    " the imports list, if so, we add it to the final list.
    let cl = a:cacheLine . ' '
    while (cl !~# '^ *$')
        let sepIdx = stridx(cl, ' ')
        let cls = strpart(cl, 0, sepIdx)
        let pat = ' ' . cls . ' '
        if (match(il, pat) >= 0)
            let rtn = rtn . cls . ' '
        endif
        let cl = strpart(cl, sepIdx + 1)
    endwhile
    "echo 'cache: ' . rtn
    " at this point we need to add the remaining imports in the rtn list.
    " get rid of the beginning space
    let mil = strpart(il, 1)
    "echo 'mil: ' . mil
    while (mil !~# '^ *$')
        let sepIdx = stridx(mil, ' ')
        let cls = strpart(mil, 0, sepIdx)
        let pat = ' ' . escape(cls, '.') . ' '
        " we add to the list if only it's not in there.
        if (match(rtn, pat) < 0)
            let rtn = rtn . cls . ' '
        endif
        let mil = strpart(mil, sepIdx + 1)
    endwhile
    " rid the head space
    let rtn = strpart(rtn, 1)
    let rtn = substitute(rtn, ' ', "\n", 'g')
    "echo 'return : ' . rtn
    return rtn
endfunction

" Save the import to the cache file.
function! s:JavaImpSaveChoice(className, imports, selected)
    let im = substitute(a:imports, "\n", ' ', 'g')
    " Note that we remove the selected first
    let spat = a:selected . ' '
    let spat = escape(spat, '.')
    let im = substitute(im, spat, '', 'g')

    let jicc = expand(g:JavaImpDataDir) . s:SL . 'choices.txt'
python << endpython
import vim
import re
import os.path

jicc = vim.eval('jicc')
className = vim.eval('a:className')
selected = vim.eval('a:selected')
im = vim.eval('im')
lines = []
idx = []

if os.path.exists(jicc):
    lines = [line.strip() for line in open(jicc, 'r')]
    idx = [i for i, line in enumerate(lines) if re.search('^%s '% className, line)]

if (len(idx) > 0):
    lines[idx[0]] = ('%s %s %s'% (className, selected, im))
else:
    lines.append('%s %s %s'% (className, selected, im))

f = open(jicc, 'w')
f.write("\n".join(lines))
f.close()
endpython
endfunction

" Choose the import if there's multiple of them.  Returns the selected import
" class.
function! s:JavaImpChooseImport(imctr, className, imports)
    let imps = s:JavaImpMakeChoice(a:imctr, a:className, a:imports)
    let uncached = (imps ==# '')
    if uncached
        let imps = a:imports
        let simps = a:imports
        " if (a:imctr > 1)
        "     let imps = "[No previous choice.  Please pick one from below...]\n".imps
        " endif
    else
        let simps = imps
    endif

    let choice = 0
    if (a:imctr > 1)
      " if the item had not been cached, we force the user to make
      " a choice, rather than letting her choose the default
      let choice = s:JavaImpDisplayChoices(imps, a:className)
      " if the choice is not cached, we don't want the user to
      " simply pick anything because he is hitting enter all the
      " time so we loop around he picks something which isn't the
      " default (earlier on, we set the default to some nonsense
      " string)
      while (uncached && choice == 0)
        let choice = s:JavaImpDisplayChoices(imps, a:className)
      endwhile
    endif

    " If cached, since we inserted the banner, we need to subtract the choice
    " by one:
    if (uncached && choice > 0)
        let choice = choice - 1
    endif

    " We run through the string again to pick the choice from the list
    " First reset the counter
    let ctr = 0
    let imps = simps
    while (imps !=# '' && imps !~# '^ *\n$')
        let sepIdx = stridx(imps, "\n")
        " Gets the substring exluding the newline
        if(sepIdx > 0)
            let imp = strpart(imps, 0, sepIdx)
        else
            let imp = imps
        endif

        if (ctr == choice)
            " We found it, we should update the choices
            "echo 'save choice simps:' . simps . ' imp: ' . imp
            call s:JavaImpSaveChoice(a:className, simps, imp)
            return imp
        endif
        let ctr = ctr + 1
        let imps = strpart(imps, sepIdx + 1, strlen(imps) - sepIdx - 1)
    endwhile
    " should not get here...
    echo 'warning: should-not-get here reached in JavaImpMakeChoice'
    return
endfunction

function! s:JavaImpDisplayChoices(imps, className)
    let imps = split(a:imps)
    let simps = imps
    let ctr = 1
    let choice = 0
    let cfmstr = ''
    let questStr =  'Multiple matches for ' . a:className . ". Your choice?\n"
    for imp in imps
        let questStr = questStr . '(' . ctr . ') ' . imp . "\n"
        let cfmstr = cfmstr . '&' . ctr . "\n"
        let ctr = ctr + 1
    endfor

    if (ctr <= 10)
        " Note that we need to get rid of the ending "\n" for it'll give
        " an extra choice in the GUI
        let cfmstr = strpart(cfmstr, 0, strlen(cfmstr) - 1)
        let choice = confirm(questStr, cfmstr, 0)
        " Note that confirms goes from 1 to 10, so if the result is not 0,
        " we need to subtract one
        if (choice != 0)
            let choice = choice - 1
        endif
    else
        let choice = input(questStr)
    endif

    return choice
endfunction

" -------------------------------------------------------------------
" Sorting
" -------------------------------------------------------------------

" Sort the import statements in the current file.
function! s:JavaImpSort()
    split

    if g:JavaImpVerbose
        let verbosity = '' 
    else
        let verbosity = 'silent'
    end

    let pkgLoc = s:JavaImpGotoPackage()
    if(pkgLoc >= 0)
        silent execute pkgLoc . 'delete p'
    endif

    let firstImp = s:JavaImpGotoFirst()
    if (firstImp < 0)
        echom 'No import statement found.'
    else
        let lastImp = s:JavaImpGotoLast()
        if (g:JavaImpSortRemoveEmpty == 1)
            call s:JavaImpRemoveEmpty(firstImp, lastImp)
            " We need to get the range again
            let firstImp = s:JavaImpGotoFirst()
            let lastImp = s:JavaImpGotoLast()
        endif

        " Sort the Import Statements using Vim's Builtin 'sort' Function.
        execute firstImp . ',' . lastImp . 'sort'

        " Reverse the Top Import List so that our insertion loop below works
        " correctly.
        let l:reversedTopImports = reverse(copy(g:JavaImpTopImports))

        " Insert each matching Top Import in Reverse Order.
        for l:pattern in l:reversedTopImports
            " Find the First Import Matching this Pattern.
            let l:firstImp = s:JavaImpGotoFirstMatchingImport(l:pattern, 'w')
            if (l:firstImp > -1)
                " Find the Last Matching Import.
                let lastImp = s:JavaImpGotoFirstMatchingImport(l:pattern, 'b')

                " Place this range of lines before that first import.
                silent execute firstImp . ',' . lastImp . 'delete l'

                exec verbosity 'call append(0, split(getreg("l"), "\n"))'
            endif
        endfor

        call s:JavaImpPlaceSortedStaticImports()

        if (g:JavaImpSortPkgSep > 0)
            " Where are All of the Imports?
            let l:firstImp = s:JavaImpGotoFirst()
            let l:lastImp = s:JavaImpGotoLast()

            " Where are the Static Imports?
            let l:firstStaticImp = s:JavaImpFindFirstStaticImport()
            let l:lastStaticImp = s:JavaImpFindLastStaticImport()

            " Update the Import Range so that the Static Imports are not
            " Included.
            if (l:firstStaticImp <= l:firstImp)
                let l:firstImp = l:lastStaticImp
            elseif (l:firstStaticImp > l:lastImp)
                let l:lastImp = l:firstStaticImp - 1
            endif

            " Add the Package Separator.
            call s:JavaImpAddPkgSep(l:firstImp, l:lastImp, g:JavaImpSortPkgSep)
        endif
    endif

    if(pkgLoc >= 0)
        exec verbosity 'call append(0, split(getreg("p"), "\n"))'
    endif

    let @l = ''
    let @p = ''

    close
endfunction

" Place Sorted Static Imports either before or after the normal imports
" depending on g:JavaImpStaticImportsFirst.
function! s:JavaImpPlaceSortedStaticImports()
    " Find the Range of Static Imports
    let firstStaticImp = s:JavaImpFindFirstStaticImport()
    if (firstStaticImp > -1)
        let lastStaticImp = s:JavaImpFindLastStaticImport()

        " Remove the block of Static Imports.
        execute firstStaticImp . ',' . lastStaticImp . 'delete'

        " Place the cursor before the Normal Imports.
        if g:JavaImpStaticImportsFirst == 1
            " Find the Line which should contain the first import.
            if (s:JavaImpGotoPackage() < 0)
                normal! ggP
            else
                normal! jp
            endif


        " Otherwise, place the cursor after the Normal Imports.
        else
            " Paste in the Static Imports after the last import or at the top
            " of the file if no other imports.
            if (s:JavaImpGotoLast() < 0)
                if (s:JavaImpGotoPackage() < 0)
                    normal! ggP
                else
                    normal! jp
                endif
            else
                normal! p
            endif
        endif

    endif
endfunction

" Remove empty lines in the range
function! s:JavaImpRemoveEmpty(fromLine, toLine)
    silent exe '' . a:fromLine . ',' . a:toLine . ' g/^\s*$/d'
endfunction

" -------------------------------------------------------------------
" Inserting spaces between packages
" -------------------------------------------------------------------

" Given a sorted range, we would like to add a new line (do a 'O')
" to seperate sections of packages.  The depth argument controls
" what we treat as a seperate section.
"
" Consider the following:
" -----
"  import java.util.TreeSet;
"  import java.util.Vector;
"  import org.apache.log4j.Logger;
"  import org.apache.log4j.spi.LoggerFactory;
"  import org.exolab.castor.xml.Marshaller;
" -----
"
" With a depth of 1, this becomes
" -----
"  import java.util.TreeSet;
"  import java.util.Vector;

"  import org.apache.log4j.Logger;
"  import org.apache.log4j.spi.LoggerFactory;
"  import org.exolab.castor.xml.Marshaller;
" -----

" With a depth of 2, it becomes
" ----
"  import java.util.TreeSet;
"  import java.util.Vector;
"
"  import org.apache.log4j.Logger;
"  import org.apache.log4j.spi.LoggerFactory;
"
"  import org.exolab.castor.xml.Marshaller;
" ----
" Depth should be >= 1, but don't set it too high, or else this function
" will split everything up.  The recommended depth setting is "2"
function! s:JavaImpAddPkgSep(fromLine, toLine, depth)
    "echo 'fromLine: ' . a:fromLine . ' toLine: ' . a:toLine." depth:".a:depth
    if (a:depth <= 0)
      return
    endif

    let cline = a:fromLine
    let endline = a:toLine
    let lastPkg = s:JavaImpGetSubPkg(getline(cline), a:depth)

    let cline = cline + 1
    while (cline <= endline)
        let thisPkg = s:JavaImpGetSubPkg(getline(cline), a:depth)

        " If last package does not equals to this package, append a line
        if (lastPkg != thisPkg)
            "echo 'last: ' . lastPkg . ' this: ' . thisPkg
            call append(cline - 1, '')
            let endline = endline + 1
            let cline = cline + 1
        endif
        let lastPkg = thisPkg
        let cline = cline + 1
    endwhile
endfunction

" Returns the full path of the Java source file or JavaDoc.
"
" Set 'ext' to:
"  .html - for JavaDoc.
"  .java - for Java files.
"
" @param basePath - the base path to search for the class.
" @param fullClassName - fully qualified class name
" @param ext - extension to search for.
function! s:JavaImpGetFile(basePath, fullClassName, ext)
    " Convert the '.' to '/'.
    let df = substitute(a:fullClassName, '\.', '/', 'g')

    " Construct the full path to the possible file.
    let h = df . a:ext
    let l:rtn = expand(a:basePath . '/' . h)

    " If the file is not readable, return an empty string.
    if filereadable(rtn) == 0
        let l:rtn = '' 
    endif
    return l:rtn
endfunction

" View the doc
function! s:JavaImpViewDoc(f)
    let cmd = '!' . g:JavaImpDocViewer . ' "' . a:f . '"'
    silent execute cmd
    " We need to redraw after we quit, for things may not refresh correctly
    redraw!
endfunction

" -------------------------------------------------------------------
" Java Source Viewing
" -------------------------------------------------------------------
function! s:JavaImpFile(doSplit)
    " We would like to save the current buffer first:
    if expand('%') !=# ''
        update
    endif

    " Class Name to search for is the Current Word.
    let className = expand('<cword>')

    " Find the fully qualified classname for this class.
    let fullClassName = s:JavaImpFindFullName(className)
    if (fullClassName ==# '')
        echo "Can't find class " . className
        return

    " Otherwise, search for the class.
    else
        let currPaths = g:JavaImpPaths

        " See if currPaths has a separator at the end, if not, we add it.
        if (match(currPaths, g:JavaImpPathSep . '$') == -1)
            let currPaths = currPaths . g:JavaImpPathSep
        endif

        while (currPaths !=# '' && currPaths !~# '^ *' . g:JavaImpPathSep . '$')
            " Find First Separator (this marks the end of the Next Path).
            let sepIdx = stridx(currPaths, g:JavaImpPathSep)

            " Retrieve the Next Path.
            let currPath = strpart(currPaths, 0, sepIdx)

            " Chop off the Next Path--this leaves only the remaining paths to
            " search.
            let currPaths = strpart(currPaths, sepIdx + 1, strlen(currPaths) - sepIdx - 1)

            if (isdirectory(currPath))
                let f = s:JavaImpGetFile(currPath, fullClassName, '.java')
                if (f !=# '')
                    if (a:doSplit == 1)
                        split
                    endif
                    exec 'edit ' . f
                    return
                endif
            endif
        endwhile
        echo 'Can not find ' . fullClassName . ' in g:JavaImpPaths'
    endif
endfunction

" -------------------------------------------------------------------
" Java Doc Viewing
" -------------------------------------------------------------------
function! s:JavaImpDoc()
    if (!exists('g:JavaImpDocPaths'))
        echo 'Error: g:JavaImpDocPaths not set.  Please see the documentation for details.'
        return
    endif

    " choose the current word for the class
    let className = expand('<cword>')
    let fullClassName = s:JavaImpFindFullName(className)
    if (fullClassName ==# '')
        return
    endif

    let currPaths = g:JavaImpDocPaths
    " See if currPaths has a separator at the end, if not, we add it.
    if (match(currPaths, g:JavaImpPathSep . '$') == -1)
        let currPaths = currPaths . g:JavaImpPathSep
    endif
    while (currPaths !=# '' && currPaths !~# '^ *' . g:JavaImpPathSep . '$')
        let sepIdx = stridx(currPaths, g:JavaImpPathSep)
        " Gets the substring exluding the newline
        let currPath = strpart(currPaths, 0, sepIdx)
        "echo "Searching in path: " . currPath
        let currPaths = strpart(currPaths, sepIdx + 1, strlen(currPaths) - sepIdx - 1)
        let docFile = s:JavaImpGetFile(currPath, fullClassName, '.html')
        if (filereadable(docFile))
            call s:JavaImpViewDoc(docFile)
            return
        endif
    endwhile
    echo 'JavaDoc not found in g:JavaImpDocPaths for class ' . fullClassName
    return
endfunction

" -------------------------------------------------------------------
" Quickfix
" -------------------------------------------------------------------

" Taken from Eric Kow's dev script...
"
" This function will try to open your error window, given that you have run Ant
" and the quickfix windows contains unresolved symbol error, will fix all of
" them for you automatically!
function! s:JavaImpQuickFix()
    if (s:JavaImpChkEnv() != 0)
        return
    endif
    " FIXME... we should figure out if there are no errors and
    " quit gracefully, rather than let vim do its error thing and
    " figure out where to stop
    crewind
    cn
    cn
    copen
    let l:nextStr = getline('.')
    echo l:nextStr
    let l:currentStr = ''

    crewind
    " we use the cn command to advance down the quickfix list until
    " we've hit the last error
    while match(l:nextStr,'|[0-9]\+ col [0-9]\+|') > -1
        " jump to the quickfix error window
        cnext
        copen
        let l:currentLine = line('.')
        let l:currentStr=getline(l:currentLine)
        let l:nextStr=getline(l:currentLine + 1)

        if (match(l:currentStr, 'cannot resolve symbol$') > -1 ||
                    \ match(l:currentStr, 'Class .* not found.$') > -1 ||
                    \ match(l:currentStr, 'Undefined variable or class name: ') > -1)

            " get the filename (we don't use this for the sort,
            " but later on when we want to sort a file's after
            " imports after inserting all the ones we know of
            let l:nextFilename = substitute(l:nextStr,  '|.*$','','g')
            let l:oldFilename = substitute(l:currentStr,'|.*$','','g')

            " jump to where the error occurred, and fix it
            cc
            call s:JavaImpInsert(0)

            " since we're still in the buffer, if the next line looks
            " like a different file (or maybe the end-of-errors), sort
            " this file's import statements
            if l:nextFilename != l:oldFilename
                call s:JavaImpSort()
            endif
        endif

        " this is where the loop checking happens
    endwhile
endfunction

" -------------------------------------------------------------------
" (Helpers) Vim-sort for those of us who don't have unix or cygwin
" -------------------------------------------------------------------

" -------------------------------------------------------------------
" (Helpers) Goto...
" -------------------------------------------------------------------

" Go to the package declaration
function! s:JavaImpGotoPackage()
    " First search for the className in an import statement
python << endpython
import vim
import re

lines = vim.current.buffer
for idx,line in enumerate(lines):
    if re.match(r"^\s*package\s\s*.*;",line):
        vim.command('return %d'% idx)
        break
endpython
    return -1
endfunction

" Go to the last import statement that it can find.  Returns 1 if an import is
" found, returns 0 if not.
function! s:JavaImpGotoLast()
    return s:JavaImpGotoFirstMatchingImport('', 'b')
endfunction

" Go to the last import statement that it can find.  Returns 1 if an import is
" found, returns 0 if not.
function! s:JavaImpGotoFirst()
    return s:JavaImpGotoFirstMatchingImport('', 'w')
endfunction

" Go to the last static import statement that it can find.  Returns 1 if an
" import is found, returns 0 if not.
function! s:JavaImpFindLastStaticImport()
    return s:JavaImpGotoFirstMatchingImport('static\s\s*', 'b')
endfunction
"
" Go to the first static import statement that it can find.  Returns 1 if an
" import is found, returns 0 if not.
function! s:JavaImpFindFirstStaticImport()
    return s:JavaImpGotoFirstMatchingImport('static\s\s*', 'w')
endfunction

function! s:JavaImpGotoFirstMatchingImport(pattern, flags)
python << endpython
import vim
import re

lines = vim.current.buffer
pattern = vim.eval('a:pattern')
flags = vim.eval('a:flags')

if flags == 'b':
    r = xrange(len(lines)-1, -1, -1)
else:
    r = xrange(0, len(lines), 1)

for i in r:
    imp = re.match(r"^\s*import\s\s*" + pattern + ".*;",lines[i])
    if imp:
        vim.command('return %d'% i)
        break
endpython
    return -1
endfunction

" -------------------------------------------------------------------
" (Helpers) Miscellaneous
" -------------------------------------------------------------------

" Removes all duplicate entries from a sorted buffer
" preserves the order of the buffer and runs in o(n) time
function! s:CheesyUniqueness() range
    let l:storedStr = getline(1)
    let l:currentLine = 2
    let l:lastLine = a:lastline
    "echo 'starting with l:storedStr '.l:storedStr.", l:currentLine '.l:currentLine.', l:lastLine".lastLine
    while l:currentLine < l:lastLine
        let l:currentStr = getline(l:currentLine)
        if l:currentStr == l:storedStr
            "echo 'deleting line '.l:currentLine
            exe l:currentLine.'delete'
            " note that we do NOT advance the currentLine counter here
            " because where currentLine is is what was once the next
            " line, but what we do have to do is to decrement what we
            " treat as the last line
            let l:lastLine = l:lastLine - 1
        else
            let l:storedStr = l:currentStr
            let l:currentLine = l:currentLine + 1
            "echo 'set new stored Str to '.l:storedStr
        endif
    endwhile
endfunction

" -------------------------------------------------------------------
" (Helpers) Making sure directory is set up
" -------------------------------------------------------------------

" Returns 0 if the directory is created successfully.  Returns non-zero
" otherwise.
function! s:JavaImpCfmMakeDir(dir)
    if (! isdirectory(a:dir))
        let input = confirm('Do you want to create the directory ' . a:dir . '?', "&Create\n&No", 1)
        if (input == 1)
            return s:JavaImpMakeDir(a:dir)
        else
            echo 'Operation aborted.'
            return 1
        endif
    endif
endfunction

function! s:JavaImpMakeDir(dir)
    if(has('unix'))
        let cmd = 'mkdir -p ' . a:dir
    elseif(has('win16') || has('win32') || has('win95') ||
                \has('dos16') || has('dos32') || has('os2'))
        let cmd = 'mkdir "' . a:dir . '"'
    else
        return 1
    endif
    call system(cmd)
    let rc = v:shell_error
    "echo 'calling ' . cmd
    return rc
endfunction

" Check and make sure the directories are set up correctly.  Otherwise, create
" the dir or complain.
function! s:JavaImpChkEnv()
    " Check if the g:JavaImpPaths is set:
    if (!exists('g:JavaImpPaths'))
        echo 'You have not set the g:JavaImpPaths variable.  Pleae see documentation for details.'
        return 1
    endif
    let rc = s:JavaImpCfmMakeDir(g:JavaImpDataDir)
    if (rc != 0)
        echo 'Error creating directory: ' . g:JavaImpDataDir
        return rc
    endif
    "echo 'Created directory: ' . g:JavaImpDataDir
    let rc = s:JavaImpCfmMakeDir(g:JavaImpJarCache)
    if (rc != 0)
        echo 'Error creating directory: ' . g:JavaImpJarCache
        return rc
    endif
    "echo 'Created directory: ' . g:JavaImpJarCache
    return 0
endfunction

" Returns the classname of an import statement
" For the string "import foo.bar.Frobnicability;"
" , this returns "Frobnicability"
"
" If not given an import statement, this returns
" empty string
function! s:JavaImpGetClassname(importStr,depth)
    let pkgMatch = '\s*import\s*.*\.[^.]*;$'
    let pkgGrep = '\s*import\s*.*\.\([^.]*\);$'

    if (match(a:importStr, pkgMatch) == -1)
        let classname = '' 
    else
        let classname = substitute(a:importStr, pkgGrep, '\1', '')
    endif
    return classname
endfunction


" Returns the (sub) package name of an import " statement.
"
" Consider the string "import foo.bar.Frobnicability;"
"
" If depth is 1, this returns "foo"
" If depth is 2, this returns "foo.bar"
" If depth >= 3, this returns "foo.bar.Frobnicability"
function! s:JavaImpGetSubPkg(importStr,depth)
    " set up the match/grep command
    let subpkgStr = '[^.]\{-}\.'
    let pkgMatch = '\s*import\s*.*\.[^.]*;$'
    let pkgGrep = '\s*import\s*\('
    let curDepth = a:depth
    " we tack on a:depth extra subpackage to the end of the match
    " and grep expressions
    while (curDepth > 0)
      let pkgGrep = pkgGrep.subpkgStr
      let curDepth = curDepth - 1
    endwhile
    let pkgGrep = pkgGrep.'\)'.'.*;$'
    " echo pkgGrep

    if (match(a:importStr, pkgMatch) == -1)
        let lastPkg = ''
    else
        let lastPkg = substitute(a:importStr, pkgGrep, '\1', '')
    endif

    " echo a:depth.' gives us '.lastPkg
    return lastPkg
endfunction
