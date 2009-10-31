#!/usr/bin/env ruby
require 'rubygems'
require 'open-uri' 
require 'nokogiri'
require 'yaml'
require 'erb'

REPOSITORY_URL = 'https://svn.micheljansen.org/onspot/trunk/'
ROOT_PATH = File.join('/','home','dawuss','svntex');
TARGET_PATH = File.join('/', 'home', 'dawuss', 'public_html', 'onspot')

class SVNExporter
  attr_reader :workdir
  
  def initialize(url, revision="HEAD", workdir=/tmp/)
    @url = url
    @revision = revision
    @workdir = workdir
  end
  
  def run    
    cleanup
    
    FileUtils.mkdir_p(@workdir)
    
    FileUtils.cd(workdir) do

      result = system "svn export -r #{@revision} #{@url}"
      if !result then
        raise "Failed to export sources. Giving up." 
      end
      
    end
    
  end
  
  def cleanup
    begin
      FileUtils.remove_entry_secure(@workdir)
      puts "cleaned up"
    rescue Exception
      puts "nothing to clean up"
    end
  end
end

class LatexBuilder
  
  def initialize(docdir, target)
    @docdir = docdir
    @target = target
  end
  
  def run
    FileUtils.cd(@docdir) do
      result = system "/bin/sh latexmk -pdf #{@target}"

      if !result then
        raise "Build failed." 
      end
    end
  end
  
  def outputfile
    File.join(@docdir, "#{@target}.pdf")
  end
  
end


class Report
  def initialize(filename)
    @filename = filename
    @data = []
  end
  
  def load()
    if(File.exists?(@filename))
      @data = YAML::load(open(@filename))
    else
      @data = []
    end
  end
  
  def append(data)
    @data << data
    yaml_string = [data].to_yaml
    yaml_lines = yaml_string.split("\n")
    yaml_lines.shift
    
    if(!File.exists?(@filename))
      File.open(@filename, 'w') do |file|
        file.write("--- \n")
      end
    end
    
    if(File.writable?(@filename))
      File.open(@filename, 'a') do |file|
        yaml_lines.each do |line|
          file.write(line)
          file.write("\n")
        end
      end
    else
      raise "file not writable"
    end
    
  end
  
  def to_html
    template = File.read("template.html.erb")
    
    ERB.new(template).result(binding)
  end
  
  def self.load(filename)
    report = Report.new(filename)
    report.load()
    return report
  end
end

def svnlook(revision, path)
  puts "using svnlook"
  output = `svnlook info -r #{revision} #{path}`
  raise "svnlook failed: #{$?.to_i} #{output}" if $?.to_i != 0
  info = output.split("\n")
  raise "svnlook failed: #{info}" if info.length < 4
  {
    :author => info[0],
    :revision => revision,
    :message => info[3]
  }
end

def svn_info(revision, url)
  puts "using svn info"
  output = `svn log -r #{revision} --xml #{url}`
  raise "svn info failed " if $?.to_i != 0  
  info = Nokogiri::XML(output)
  {
    :author => info.search('author').inner_text,
    :revision => info.search('logentry').first['revision'].to_i,
    :message => info.search('msg').inner_text
  }
end

def is_revision_number(rev)
  !rev.to_s.match(/^\d+$/).nil?
end

#### BEGIN WORKING ####
repository_path = ARGV.length >= 1 ? ARGV[0] : nil
revision = ARGV.length >= 2 ? ARGV[1] : "HEAD"
workdir = File.join(ROOT_PATH, 'temp')

exporter = SVNExporter.new(REPOSITORY_URL, revision, workdir)
status = "ok"

info = {
    :revision => revision,
    :author => "unknown",
    :message => ""
  }

begin
  puts "processing revision #{revision}"
  puts "getting info..."
  
  info = (!repository_path.nil? && is_revision_number(revision)) ? svnlook(revision, repository_path) : svn_info(revision, REPOSITORY_URL)
  
  puts "exporting..."
  exporter.run
  revision = info[:revision] #freeze special cases, such as HEAD, PREV etc.
  
  puts "building..."
  docdir = File.join(exporter.workdir, 'trunk', 'report')
  builder = LatexBuilder.new(docdir, 'report')
  builder.run
  puts "done!"
  
  FileUtils.mv(builder.outputfile, File.join(TARGET_PATH, "report-#{revision}.pdf"));
  
rescue Exception => e
  status = "ERROR: #{e}"
  puts status
ensure
  exporter.cleanup
  report = Report.load(File.join(ROOT_PATH, 'entries_db.yaml'))
  report.append({
    :revision => info[:revision], 
    :author => info[:author],
    :message => info[:message],
    :info => status,
    :file => "report-#{revision}.pdf"})
    
  puts report.to_html
end