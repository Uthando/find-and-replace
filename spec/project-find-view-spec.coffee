os = require 'os'
path = require 'path'

{_, fs, $, View, WorkspaceView} = require 'atom'
Q = require 'q'

ResultsPaneView = require '../lib/project/results-pane'

# Default to 30 second promises
waitsForPromise = (fn) -> window.waitsForPromise timeout: 30000, fn

describe 'ProjectFindView', ->
  [pack, editor, projectFindView, searchPromise, resultsPane] = []

  getExistingResultsPane = ->
    pane = atom.workspaceView.panes.paneForUri(ResultsPaneView.URI)
    return pane.itemForUri(ResultsPaneView.URI) if pane?
    null

  beforeEach ->
    atom.workspaceView = new WorkspaceView()
    atom.project.setPath(path.join(__dirname, 'fixtures'))
    atom.workspaceView.attachToDom()
    pack = atom.packages.activatePackage("find-and-replace", immediate: true)
    pack.mainModule.createProjectFindView()
    projectFindView = pack.mainModule.projectFindView

    atom.config.set('find-and-replace.openProjectFindResultsInRightPane', false)

    spy = spyOn(projectFindView, 'confirm').andCallFake ->
      searchPromise = spy.originalValue.call(projectFindView)
      resultsPane = atom.workspaceView.find('.preview-pane').view()
      searchPromise

    liveSpy = spyOn(projectFindView, 'liveSearch').andCallFake (options) ->
      searchPromise = liveSpy.originalValue.call(projectFindView, options)
      resultsPane = atom.workspaceView.find('.preview-pane').view()
      searchPromise

  describe "when project-find:show is triggered", ->
    beforeEach ->
      projectFindView.findEditor.setText('items')

    it "attaches ProjectFindView to the root view", ->
      atom.workspaceView.trigger 'project-find:show'
      expect(atom.workspaceView.find('.project-find')).toExist()
      expect(projectFindView.find('.preview-block')).not.toBeVisible()
      expect(projectFindView.find('.loading')).not.toBeVisible()
      expect(projectFindView.findEditor.getSelectedBufferRange()).toEqual [[0, 0], [0, 5]]

    describe "with an open buffer", ->
      beforeEach ->
        projectFindView.findEditor.setText('')
        atom.workspaceView.openSync('sample.js')
        editor = atom.workspaceView.getActiveView()

      it "populates the findEditor with selection when there is a selection", ->
        editor.setSelectedBufferRange([[2, 8], [2, 13]])
        atom.workspaceView.trigger 'project-find:show'
        expect(atom.workspaceView.find('.project-find')).toExist()
        expect(projectFindView.findEditor.getText()).toBe('items')

        projectFindView.findEditor.setText('')

        editor.setSelectedBufferRange([[2, 14], [2, 20]])
        atom.workspaceView.trigger 'project-find:show'
        expect(atom.workspaceView.find('.project-find')).toExist()
        expect(projectFindView.findEditor.getText()).toBe('length')

    describe "when thethe ProjectFindView is already attached", ->
      beforeEach ->
        atom.workspaceView.trigger 'project-find:show'
        projectFindView.findEditor.setSelectedBufferRange([[0, 0], [0, 0]])

      it "focuses the find editor and selects all the text", ->
        atom.workspaceView.trigger 'project-find:show'
        expect(projectFindView.findEditor.find(':focus')).toExist()
        expect(projectFindView.findEditor.getSelectedText()).toBe "items"

  describe "when project-find:show-in-current-directory is triggered", ->
    [nested, tree] = []

    class DirElement extends View
      @content: (path) ->
        @div class: 'directory', =>
          @div class: 'nested-thing', =>
            @span outlet: 'name', class: 'name', path
            @ul outlet: 'files', class: 'files'
      initialize: (@path) ->
      getPath: -> @path
      createFiles: (names) ->
        for name in names
          @files.append(new FileElement(path.join(@path, name)))

    class FileElement extends View
      @content: (path) ->
        @li class: 'file', =>
          @span outlet: 'name', class: 'name', path
      initialize: (@path) ->
      getPath: -> @path

    beforeEach ->
      projectFindView.findEditor.setText('items')

      p = atom.project.getPath()
      tree = new DirElement(p)
      tree.createFiles(['one.js', 'two.js'])

      nested = new DirElement(path.join(p, 'nested'))
      nested.createFiles([path.join('nested', 'another.js')])

      tree.files.append(nested)
      atom.workspaceView.append(tree)

    it "populates the pathsEditor when triggered with a directory", ->
      nested.name.trigger 'project-find:show-in-current-directory'
      expect(atom.workspaceView.find('.project-find')).toExist()
      expect(projectFindView.pathsEditor.getText()).toBe('nested')

      tree.name.trigger 'project-find:show-in-current-directory'
      expect(projectFindView.pathsEditor.getText()).toBe('')

    it "populates the pathsEditor when triggered with a file", ->
      nested.files.find('> .file:eq(0)').view().name.trigger 'project-find:show-in-current-directory'
      expect(atom.workspaceView.find('.project-find')).toExist()
      expect(projectFindView.pathsEditor.getText()).toBe('nested')

      tree.files.find('> .file:eq(0)').view().name.trigger 'project-find:show-in-current-directory'
      expect(projectFindView.pathsEditor.getText()).toBe('')

  describe "finding", ->
    beforeEach ->
      atom.workspaceView.openSync('sample.js')
      editor = atom.workspaceView.getActiveView()

    describe "when core:cancel is triggered", ->
      beforeEach ->
        atom.workspaceView.trigger 'project-find:show'
        projectFindView.focus()

      it "detaches from the root view", ->
        $(document.activeElement).trigger 'core:cancel'
        expect(atom.workspaceView.find('.project-find')).not.toExist()

    describe "splitting into a second pane", ->
      beforeEach ->
        atom.workspaceView.height(1000)

        editor.trigger 'project-find:show'

      it "splits when option is true", ->
        initialPane = atom.workspaceView.getActivePane()
        atom.config.set('find-and-replace.openProjectFindResultsInRightPane', true)
        projectFindView.findEditor.setText('items')
        projectFindView.trigger 'core:confirm'

        waitsForPromise ->
          searchPromise

        runs ->
          pane1 = atom.workspaceView.getActivePane()
          expect(pane1[0]).not.toBe initialPane[0]

      it "does not split when option is false", ->
        initialPane = atom.workspaceView.getActivePane()
        projectFindView.findEditor.setText('items')
        projectFindView.trigger 'core:confirm'

        waitsForPromise ->
          searchPromise

        runs ->
          pane1 = atom.workspaceView.getActivePane()
          expect(pane1[0]).toBe initialPane[0]

      it "can be duplicated", ->
        atom.config.set('find-and-replace.openProjectFindResultsInRightPane', true)
        projectFindView.findEditor.setText('items')
        projectFindView.trigger 'core:confirm'

        waitsForPromise ->
          searchPromise

        runs ->
          resultsPaneView1 = getExistingResultsPane()
          pane1 = atom.workspaceView.getActivePane()
          pane1.splitRight(pane1.copyActiveItem())

          pane2 = atom.workspaceView.getActivePane()
          resultsPaneView2 = pane2.itemForUri(ResultsPaneView.URI)

          expect(pane1[0]).not.toBe pane2[0]
          expect(resultsPaneView1[0]).not.toBe resultsPaneView2[0]

          length = resultsPaneView1.find('li > ul > li').length
          expect(length).toBeGreaterThan 0
          expect(resultsPaneView2.find('li > ul > li')).toHaveLength length

          expect(resultsPaneView2.previewCount.html()).toEqual resultsPaneView1.previewCount.html()

    describe "live searching when user types in the find box", ->
      triggerBufferModified = ->
        advanceClock(projectFindView.findEditor.getBuffer().stoppedChangingDelay + 1)

      describe "when no search has been run yet", ->
        beforeEach ->
          spyOn(atom.project, 'scan')

        it "does not run the search", ->
          projectFindView.findEditor.setText('items')
          triggerBufferModified()
          expect(atom.project.scan).not.toHaveBeenCalled()

      describe "when a search has been run already and the results have been closed", ->
        beforeEach ->
          spyOn(atom.project, 'scan').andCallFake -> Q()
          projectFindView.findEditor.setText('items')
          projectFindView.trigger 'core:confirm'
          waitsForPromise -> searchPromise
          runs ->
            atom.workspaceView.getActivePane().destroyItem(getExistingResultsPane())
            atom.project.scan.reset()

        it "displays the results and no errors", ->
          projectFindView.findEditor.setText('sort')
          triggerBufferModified()
          expect(atom.project.scan).not.toHaveBeenCalled()

        it "will run the search again when the pane is opened again", ->
          projectFindView.trigger 'core:confirm'
          waitsForPromise -> searchPromise

          runs ->
            projectFindView.findEditor.setText('sort')
            triggerBufferModified()
            expect(atom.project.scan).toHaveBeenCalled()

      describe "when a search has been run already", ->
        beforeEach ->
          projectFindView.findEditor.setText('items')
          projectFindView.trigger 'core:confirm'
          waitsForPromise -> searchPromise

        it "finds results for the new find pattern", ->
          expect(projectFindView.descriptionLabel.text()).toContain "13 results"

          projectFindView.findEditor.setText('sort')
          triggerBufferModified()

          waitsForPromise -> searchPromise

          runs ->
            expect(projectFindView.descriptionLabel.text()).toContain "10 results found in 2 files"

    describe "serialization", ->
      it "serializes if the view is attached", ->
        expect(projectFindView.hasParent()).toBeFalsy()
        editor.trigger 'project-find:show'
        atom.packages.deactivatePackage("find-and-replace")
        pack = atom.packages.activatePackage("find-and-replace", immediate: true)
        pack.mainModule.createProjectFindView()
        projectFindView = pack.mainModule.projectFindView

        expect(projectFindView.hasParent()).toBeTruthy()

      it "serializes if the case and regex options", ->
        editor.trigger 'project-find:show'
        expect(projectFindView.caseOptionButton).not.toHaveClass('selected')
        projectFindView.caseOptionButton.click()
        expect(projectFindView.caseOptionButton).toHaveClass('selected')

        expect(projectFindView.regexOptionButton).not.toHaveClass('selected')
        projectFindView.regexOptionButton.click()
        expect(projectFindView.regexOptionButton).toHaveClass('selected')

        atom.packages.deactivatePackage("find-and-replace")
        pack = atom.packages.activatePackage("find-and-replace", immediate: true)
        pack.mainModule.createProjectFindView()
        projectFindView = pack.mainModule.projectFindView

        expect(projectFindView.caseOptionButton).toHaveClass('selected')
        expect(projectFindView.regexOptionButton).toHaveClass('selected')

    describe "regex", ->
      beforeEach ->
        editor.trigger 'project-find:show'
        projectFindView.findEditor.setText('i(\\w)ems+')
        spyOn(atom.project, 'scan').andCallFake -> Q()

      it "escapes regex patterns by default", ->
        projectFindView.trigger 'core:confirm'
        expect(atom.project.scan.argsForCall[0][0]).toEqual /i\(\\w\)ems\+/gi

      describe "when search has not been run yet", ->
        it "toggles regex option via an event but does not run the search", ->
          expect(projectFindView.regexOptionButton).not.toHaveClass('selected')
          projectFindView.trigger 'project-find:toggle-regex-option'
          expect(projectFindView.regexOptionButton).toHaveClass('selected')
          expect(atom.project.scan).not.toHaveBeenCalled()

      describe "when search has been run", ->
        beforeEach ->
          projectFindView.trigger 'core:confirm'
          waitsForPromise -> searchPromise

        it "toggles regex option via an event and finds files matching the pattern", ->
          expect(projectFindView.regexOptionButton).not.toHaveClass('selected')
          projectFindView.trigger 'project-find:toggle-regex-option'
          expect(projectFindView.regexOptionButton).toHaveClass('selected')
          expect(atom.project.scan.mostRecentCall.args[0]).toEqual /i(\w)ems+/gi

        it "toggles regex option via a button and finds files matching the pattern", ->
          expect(projectFindView.regexOptionButton).not.toHaveClass('selected')
          projectFindView.regexOptionButton.click()
          expect(projectFindView.regexOptionButton).toHaveClass('selected')
          expect(atom.project.scan.mostRecentCall.args[0]).toEqual /i(\w)ems+/gi

    describe "case sensitivity", ->
      beforeEach ->
        editor.trigger 'project-find:show'
        spyOn(atom.project, 'scan').andCallFake -> Q()
        projectFindView.findEditor.setText('ITEMS')
        projectFindView.trigger 'core:confirm'
        waitsForPromise -> searchPromise

      it "runs a case insensitive search by default", ->
        expect(atom.project.scan.argsForCall[0][0]).toEqual /ITEMS/gi

      it "toggles case sensitive option via an event and finds files matching the pattern", ->
        expect(projectFindView.caseOptionButton).not.toHaveClass('selected')
        projectFindView.trigger 'project-find:toggle-case-option'
        expect(projectFindView.caseOptionButton).toHaveClass('selected')
        expect(atom.project.scan.mostRecentCall.args[0]).toEqual /ITEMS/g

      it "toggles case sensitive option via a button and finds files matching the pattern", ->
        expect(projectFindView.caseOptionButton).not.toHaveClass('selected')
        projectFindView.caseOptionButton.click()
        expect(projectFindView.caseOptionButton).toHaveClass('selected')
        expect(atom.project.scan.mostRecentCall.args[0]).toEqual /ITEMS/g

    describe "when core:confirm is triggered", ->
      beforeEach ->
        atom.workspaceView.trigger 'project-find:show'

      describe "when the there search field is empty", ->
        it "does not run the seach but clears the model", ->
          spyOn(atom.project, 'scan')
          spyOn(projectFindView.model, 'clear')
          projectFindView.trigger 'core:confirm'
          expect(atom.project.scan).not.toHaveBeenCalled()
          expect(projectFindView.model.clear).toHaveBeenCalled()

      describe "when results exist", ->
        beforeEach ->
          projectFindView.findEditor.setText('items')

        it "displays the results and no errors", ->
          projectFindView.trigger 'core:confirm'

          waitsForPromise ->
            searchPromise

          runs ->
            resultsPaneView = getExistingResultsPane()
            resultsView = resultsPaneView.resultsView
            expect(resultsView).toBeVisible()
            resultsView.scrollToBottom() # To load ALL the results
            expect(resultsView.find("li > ul > li")).toHaveLength(13)
            expect(resultsPaneView.previewCount.text()).toBe "13 results found in 2 files for items"
            expect(projectFindView.errorMessages).not.toBeVisible()

        it "only searches paths matching text in the path filter", ->
          spyOn(atom.project, 'scan').andCallFake -> Q()
          projectFindView.pathsEditor.setText('*.js')
          projectFindView.trigger 'core:confirm'

          expect(atom.project.scan.argsForCall[0][1]['paths']).toEqual ['*.js']

        it "updates the results list when a buffer changes", ->
          projectFindView.trigger 'core:confirm'
          buffer = atom.project.bufferForPathSync('sample.js')

          waitsForPromise ->
            searchPromise

          runs ->
            resultsPaneView = getExistingResultsPane()
            resultsView = resultsPaneView.resultsView
            resultsView.scrollToBottom() # To load ALL the results
            expect(resultsView.find("li > ul > li")).toHaveLength(13)
            expect(resultsPaneView.previewCount.text()).toBe "13 results found in 2 files for items"

            resultsView.selectFirstResult()
            _.times 7, -> resultsView.selectNextResult()

            expect(resultsView.find("li > ul:eq(1) > li:eq(0)")).toHaveClass 'selected'

            buffer.setText('there is one "items" in this file')
            buffer.emit('contents-modified')

            expect(resultsView.find("li > ul > li")).toHaveLength(8)
            expect(resultsPaneView.previewCount.text()).toBe "8 results found in 2 files for items"
            expect(resultsView.find("li > ul:eq(1) > li:eq(0)")).toHaveClass 'selected'

            buffer.setText('no matches in this file')
            buffer.emit('contents-modified')

            expect(resultsView.find("li > ul > li")).toHaveLength(7)
            expect(resultsPaneView.previewCount.text()).toBe "7 results found in 1 file for items"

      describe "when no results exist", ->
        beforeEach ->
          projectFindView.findEditor.setText('notintheprojectbro')
          spyOn(atom.project, 'scan').andCallFake -> Q()

        it "displays no errors and no results", ->
          projectFindView.trigger 'core:confirm'

          waitsForPromise ->
            searchPromise

          runs ->
            resultsView = getExistingResultsPane().resultsView
            expect(projectFindView.errorMessages).not.toBeVisible()
            expect(resultsView).toBeVisible()
            expect(resultsView.find("li > ul > li")).toHaveLength(0)

    describe "history", ->
      beforeEach ->
        atom.workspaceView.trigger 'project-find:show'
        spyOn(atom.project, 'scan').andCallFake -> Q()

        projectFindView.findEditor.setText('sort')
        projectFindView.replaceEditor.setText('bort')
        projectFindView.pathsEditor.setText('abc')
        projectFindView.findEditor.trigger 'core:confirm'

        projectFindView.findEditor.setText('items')
        projectFindView.replaceEditor.setText('eyetims')
        projectFindView.pathsEditor.setText('def')
        projectFindView.findEditor.trigger 'core:confirm'

      it "can navigate the entire history stack", ->
        expect(projectFindView.findEditor.getText()).toEqual 'items'

        projectFindView.findEditor.trigger 'core:move-up'
        expect(projectFindView.findEditor.getText()).toEqual 'sort'

        projectFindView.findEditor.trigger 'core:move-down'
        expect(projectFindView.findEditor.getText()).toEqual 'items'

        projectFindView.findEditor.trigger 'core:move-down'
        expect(projectFindView.findEditor.getText()).toEqual ''

        expect(projectFindView.pathsEditor.getText()).toEqual 'def'

        projectFindView.pathsEditor.trigger 'core:move-up'
        expect(projectFindView.pathsEditor.getText()).toEqual 'abc'

        projectFindView.pathsEditor.trigger 'core:move-down'
        expect(projectFindView.pathsEditor.getText()).toEqual 'def'

        projectFindView.pathsEditor.trigger 'core:move-down'
        expect(projectFindView.pathsEditor.getText()).toEqual ''

        expect(projectFindView.replaceEditor.getText()).toEqual 'eyetims'

        projectFindView.replaceEditor.trigger 'core:move-up'
        expect(projectFindView.replaceEditor.getText()).toEqual 'bort'

        projectFindView.replaceEditor.trigger 'core:move-down'
        expect(projectFindView.replaceEditor.getText()).toEqual 'eyetims'

        projectFindView.replaceEditor.trigger 'core:move-down'
        expect(projectFindView.replaceEditor.getText()).toEqual ''

    describe "when find-and-replace:set-find-pattern is triggered", ->
      it "places the selected text into the find editor", ->
        editor.setSelectedBufferRange([[1,6],[1,10]])
        atom.workspaceView.trigger 'find-and-replace:use-selection-as-find-pattern'

        expect(projectFindView.findEditor.getText()).toBe 'sort'

  describe "replacing", ->
    [testDir, sampleJs, sampleCoffee, replacePromise] = []

    beforeEach ->
      testDir = path.join(os.tmpdir(), "atom-find-and-replace")
      fs.makeTreeSync(testDir)
      sampleJs = path.join(testDir, 'sample.js')
      sampleCoffee = path.join(testDir, 'sample.coffee')

      fs.writeFileSync(sampleCoffee, fs.readFileSync(require.resolve('./fixtures/sample.coffee')))
      fs.writeFileSync(sampleJs, fs.readFileSync(require.resolve('./fixtures/sample.js')))
      atom.workspaceView.trigger 'project-find:show'
      atom.project.setPath(testDir)

      spy = spyOn(projectFindView, 'replaceAll').andCallFake ->
        replacePromise = spy.originalValue.call(projectFindView)

    afterEach ->
      # On Windows, you can not remove a watched directory/file, therefore we
      # have to close the project before attempting to delete. Unfortunately,
      # Pathwatcher's close function is also not synchronous. Once
      # atom/node-pathwatcher#4 is implemented this should be alot cleaner.
      activePane = atom.workspaceView.getActivePane()
      for item in (activePane?.getItems() or [])
        spyOn(item, 'shouldPromptToSave').andReturn(false) if item.shouldPromptToSave?
        activePane.destroyItem(item)

      success = false
      runs ->
        retry = setInterval ->
          try
            fs.removeSync(testDir)
            success = true
            clearInterval(retry)
          catch e
            success = false
        , 50
      waitsFor -> success

    describe "when the replace button is pressed", ->
      it "runs the search, and replaces all the matches", ->
        projectFindView.findEditor.setText('items')
        projectFindView.trigger 'core:confirm'

        waitsForPromise ->
          searchPromise

        runs ->
          projectFindView.replaceEditor.setText('sunshine')
          projectFindView.replaceAllButton.click()

        waitsForPromise ->
          replacePromise

        runs ->
          expect(projectFindView.errorMessages).not.toBeVisible()
          expect(projectFindView.descriptionLabel.text()).toContain 'Replaced'

          sampleJsContent = fs.readFileSync(sampleJs, 'utf8')
          expect(sampleJsContent.match(/items/g)).toBeFalsy()
          expect(sampleJsContent.match(/sunshine/g)).toHaveLength 6

          sampleCoffeeContent = fs.readFileSync(sampleCoffee, 'utf8')
          expect(sampleCoffeeContent.match(/items/g)).toBeFalsy()
          expect(sampleCoffeeContent.match(/sunshine/g)).toHaveLength 7

      describe "when there are search results after a replace", ->
        it "runs the search after the replace", ->
          projectFindView.findEditor.setText('items')
          projectFindView.trigger 'core:confirm'

          waitsForPromise ->
            searchPromise

          runs ->
            projectFindView.replaceEditor.setText('items-123')
            projectFindView.replaceAllButton.click()

          waitsForPromise ->
            replacePromise

          runs ->
            expect(projectFindView.errorMessages).not.toBeVisible()

            expect(resultsPane.previewCount.text()).toContain '13 results found in 2 files for items'
            expect(projectFindView.descriptionLabel.text()).toContain 'Replaced items with items-123 13 times in 2 files'

            projectFindView.replaceEditor.setText('cats')
            advanceClock(projectFindView.replaceEditor.getBuffer().stoppedChangingDelay)

            expect(projectFindView.descriptionLabel.text()).not.toContain 'Replaced items'
            expect(projectFindView.descriptionLabel.text()).toContain "13 results found in 2 files for items"

    describe "when the project-find:replace-all is triggered", ->
      describe "when there are no results", ->
        it "doesnt replace anything", ->
          projectFindView.findEditor.setText('nopenotinthefile')
          projectFindView.replaceEditor.setText('sunshine')

          spyOn(atom.project, 'scan').andCallThrough()
          spyOn(atom, 'beep')
          projectFindView.trigger 'project-find:replace-all'

          waitsForPromise ->
            replacePromise

          runs ->
            expect(atom.project.scan).toHaveBeenCalled()
            expect(atom.beep).toHaveBeenCalled()
            expect(projectFindView.descriptionLabel.text()).toContain "Nothing replaced"

      describe "when no search has been run", ->
        it "runs the search then replaces everything", ->
          projectFindView.findEditor.setText('items')
          projectFindView.replaceEditor.setText('sunshine')

          projectFindView.trigger 'project-find:replace-all'

          waitsForPromise ->
            replacePromise

          runs ->
            expect(projectFindView.descriptionLabel.text()).toContain "Replaced items with sunshine 13 times in 2 files"

      describe "when the search text has changed since that last search", ->
        beforeEach ->
          projectFindView.findEditor.setText('items')
          projectFindView.trigger 'core:confirm'

          waitsForPromise ->
            searchPromise

        it "clears the search results and does another replace", ->
          spyOn(atom.project, 'scan').andCallThrough()
          spyOn(atom, 'beep')

          projectFindView.findEditor.setText('sort')
          projectFindView.replaceEditor.setText('ok')
          expect(projectFindView.resultsView).not.toBeVisible()

          projectFindView.trigger 'project-find:replace-all'

          waitsForPromise ->
            replacePromise

          runs ->
            expect(atom.project.scan).toHaveBeenCalled()
            expect(atom.beep).not.toHaveBeenCalled()
            expect(projectFindView.descriptionLabel.text()).toContain "Replaced sort with ok 10 times in 2 files"

      describe "when the text in the search box triggered the results", ->
        beforeEach ->
          projectFindView.findEditor.setText('items')
          projectFindView.trigger 'core:confirm'

          waitsForPromise ->
            searchPromise

        it "runs the search, and replaces all the matches", ->
          projectFindView.replaceEditor.setText('sunshine')
          projectFindView.trigger 'project-find:replace-all'
          expect(projectFindView.errorMessages).not.toBeVisible()

          waitsForPromise ->
            replacePromise

          runs ->
            resultsPaneView = getExistingResultsPane()
            resultsView = resultsPaneView.resultsView

            expect(resultsView).toBeVisible()
            expect(resultsView.find("li > ul > li")).toHaveLength(0)

            expect(projectFindView.descriptionLabel.text()).toContain "Replaced items with sunshine 13 times in 2 files"

            sampleJsContent = fs.readFileSync(sampleJs, 'utf8')
            expect(sampleJsContent.match(/items/g)).toBeFalsy()
            expect(sampleJsContent.match(/sunshine/g)).toHaveLength 6

            sampleCoffeeContent = fs.readFileSync(sampleCoffee, 'utf8')
            expect(sampleCoffeeContent.match(/items/g)).toBeFalsy()
            expect(sampleCoffeeContent.match(/sunshine/g)).toHaveLength 7
