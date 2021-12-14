/*
 * Copyright (c) 2016-present Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import RxSwift
import RxCocoa
import Kingfisher

class ActivityController: UITableViewController {

  private let repo = "ReactiveX/RxSwift"

  private let events = Variable<[Event]>([])
  private let bag = DisposeBag()
    private let eventsFileUrl = cachedFileURL("events.plist")
    private let modifiedFileUrl = cachedFileURL("modified.txt")
    private let modifiedString = Variable<NSString?>(nil)

  override func viewDidLoad() {
    super.viewDidLoad()
    title = repo

    self.refreshControl = UIRefreshControl()
    let refreshControl = self.refreshControl!

    refreshControl.backgroundColor = UIColor(white: 0.98, alpha: 1.0)
    refreshControl.tintColor = UIColor.darkGray
    refreshControl.attributedTitle = NSAttributedString(string: "Pull to refresh")
    refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)

    let eventsArray = (NSArray(contentsOf: eventsFileUrl) as? [[String: Any]]) ?? []
    events.value = eventsArray.compactMap{ event in
        Event.init(dictionary: event)
    }

    modifiedString.value = try? NSString(contentsOf: modifiedFileUrl, usedEncoding: nil)

    refresh()
  }

  @objc func refresh() {
    DispatchQueue.global(qos: .background).async { [weak self] in
      guard let strongSelf = self else { return }
      strongSelf.fetchEvents(repo: strongSelf.repo)
    }
  }

    func fetchEvents(repo: String) {
        let response = Observable.from([repo]).map { urlString in
            URL(string: "https://api.github.com/repos/\(urlString)/events")!
        }.map { url in
            var request = URLRequest(url: url)
            if let modifiedHeader = self.modifiedString.value {
                request.addValue(modifiedHeader as String, forHTTPHeaderField: "Last-Modified")
            }
            return request
        }.flatMap { request -> Observable<(response: HTTPURLResponse, data: Data)> in
            URLSession.shared.rx.response(request: request)
        }.share(replay: 1, scope: .whileConnected)

        response.filter { (response, _) -> Bool in
            return 200...300 ~= response.statusCode
        }.map { (_, data) -> [[String: Any]] in
            guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                let result = jsonObject as? [[String: Any]] else { return [] }
            return result
        }.filter { (objects) -> Bool in
            objects.count > 0
        }.map { (objects) in
            return objects.compactMap { (object) in
                return Event.init(dictionary: object)
            }
        }.subscribe(onNext: { [unowned self] (newEvent) in
            self.processEvents(newEvent)
        }).disposed(by: bag)

        response.filter { (response, _) -> Bool in
            return 200..<400 ~= response.statusCode
        }.flatMap { (response, _) -> Observable<NSString> in
            guard let value = response.allHeaderFields["Last-Modified"] as? NSString else {
                return Observable<NSString>.empty()
            }
            return Observable<NSString>.just(value)
        }.subscribe(onNext: { [unowned self] (modifiedHeader) in
            self.modifiedString.value = modifiedHeader
            try? modifiedHeader.write(to: self.modifiedFileUrl, atomically: true, encoding: String.Encoding.utf8.rawValue)
        }).disposed(by: bag)

    }

    func processEvents(_ newEvents: [Event]) {
        var updatedEvents = newEvents + events.value
        if updatedEvents.count > 50 {
            updatedEvents = Array<Event>(updatedEvents.prefix(upTo: 50))
        }
        events.value = updatedEvents
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            self.tableView.reloadData()
            self.refreshControl?.endRefreshing()
        }

        let eventsArray = updatedEvents.map { [unowned self] (event) in
            event.dictionary
        } as NSArray

        eventsArray.write(to: eventsFileUrl, atomically: true)

    }



  // MARK: - Table Data Source
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return events.value.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let event = events.value[indexPath.row]

    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!
    cell.textLabel?.text = event.name
    cell.detailTextLabel?.text = event.repo + ", " + event.action.replacingOccurrences(of: "Event", with: "").lowercased()
    cell.imageView?.kf.setImage(with: event.imageUrl, placeholder: UIImage(named: "blank-avatar"))
    return cell
  }
}

func cachedFileURL(_ fileName: String) -> URL {
    return FileManager.default.urls(for: .cachesDirectory, in: .allDomainsMask).first!.appendingPathComponent(fileName)
}
